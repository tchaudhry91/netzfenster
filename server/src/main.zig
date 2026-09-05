const std = @import("std");
const Io = std.Io;

const lib = @import("server");

const log = std.log.scoped(.server);
const http_log = std.log.scoped(.http);

pub fn main(init: std.process.Init) !void {
    const gpa: std.mem.Allocator = std.heap.page_allocator;
    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();

    // Accessing command line arguments:
    const args = try init.minimal.args.toSlice(arena.allocator());
    _ = args; // Not needed for now

    // In order to do I/O operations need an `Io` instance.
    const io = init.io;

    // Stdout is for the actual output of your application, for example if you
    // are implementing gzip, then only the compressed bytes should be sent to
    // stdout, not any debugging messages.
    var stdout_buffer: [1024]u8 = undefined;
    var stdout_file_writer: Io.File.Writer = .init(.stdout(), io, &stdout_buffer);
    const stdout_writer = &stdout_file_writer.interface;

    // Get Base Vars
    const data_dir = init.environ_map.get("NETZF_HOME") orelse "/opt/netzf";
    const listen_addr = init.environ_map.get("NETZF_LISTEN_ADDR") orelse "127.0.0.1:8989";

    const config = lib.Config{
        .listen_addr = listen_addr,
        .base_dir_path = data_dir,
    };

    const ip_addr = try std.Io.net.IpAddress.parseLiteral(config.listen_addr);

    var listener = try ip_addr.listen(io, .{ .reuse_address = true });
    defer listener.deinit(io);
    log.info("listening on {s}", .{listen_addr});
    log.info("data dir: {s}", .{data_dir});
    // Accept Loop
    while (true) {
        const stream = try listener.accept(io);
        handleFrameRequest(stream, gpa, io, config) catch {
            continue;
        };
    }
    try stdout_writer.flush();
}

fn handleFrameRequest(
    stream: std.Io.net.Stream,
    gpa: std.mem.Allocator,
    io: std.Io,
    config: lib.Config,
) !void {
    var local_arena = std.heap.ArenaAllocator.init(gpa);
    defer local_arena.deinit();
    const allocator = local_arena.allocator();
    defer stream.close(io);

    var read_buf: [4096]u8 = undefined;
    var write_buf: [4096]u8 = undefined;

    var reader = stream.reader(io, &read_buf);
    var writer = stream.writer(io, &write_buf);

    var http_server = std.http.Server.init(&reader.interface, &writer.interface);
    var req = try http_server.receiveHead();
    if (req.head.method != .GET) {
        http_log.warn("{s} {s} -> 405", .{ @tagName(req.head.method), req.head.target });
        try req.respond("MethodNotAllowed", .{ .keep_alive = false, .status = .method_not_allowed });
        return error.MethodNotAllowed;
    }
    const f_req = parseFrameRequest(allocator, req.head.target) catch |err| {
        http_log.err("{s} {s} -> 400: {any}", .{ @tagName(req.head.method), req.head.target, err });
        try req.respond("Error in Parsing Frame Request", .{ .status = .bad_request });
        return error.BadRequest;
    };
    const serialized_vp = lib.serializeViewPort(allocator, io, f_req.ViewPort, config, @intCast(f_req.Rows), @intCast(f_req.Cols)) catch |err| {
        http_log.err("{s} {s} -> 500: {any}", .{ @tagName(req.head.method), req.head.target, err });
        try req.respond("Error in executing viewport", .{ .status = .internal_server_error });
        return error.ViewportError;
    };
    try req.respond(serialized_vp, .{ .status = .ok, .extra_headers = &.{std.http.Header{ .name = "content-type", .value = "application/json" }} });
    http_log.info("{s} {s} -> 200", .{ @tagName(req.head.method), req.head.target });
}

const FrameRequest = struct {
    ViewPort: []const u8,
    Rows: usize,
    Cols: usize,
};

fn parseFrameRequest(allocator: std.mem.Allocator, target: []const u8) !FrameRequest {
    var f_req: FrameRequest = FrameRequest{
        .Cols = 21,
        .Rows = 8,
        .ViewPort = &.{},
    };
    const path_query = std.mem.cutScalar(u8, target, '?');
    if (path_query == null) {
        return error.RowColsNotFound;
    }
    const path = path_query.?.@"0";
    const query = path_query.?.@"1";

    if (!std.mem.eql(u8, path, "/frame")) {
        return error.InvalidPath;
    }
    var params = std.mem.splitScalar(u8, query, '&');

    while (params.next()) |param| {
        const Key = enum {
            ROWS,
            COLS,
            VIEWPORT,
        };

        var key: ?Key = null;

        if (std.mem.startsWith(u8, param, "rows")) {
            key = .ROWS;
        }

        if (std.mem.startsWith(u8, param, "cols")) {
            key = .COLS;
        }

        if (std.mem.startsWith(u8, param, "viewport")) {
            key = .VIEWPORT;
        }

        if (key == null) {
            continue;
        }

        const kv = std.mem.cutScalar(u8, param, '=').?;

        switch (key.?) {
            Key.ROWS => {
                f_req.Rows = try std.fmt.parseInt(usize, kv.@"1", 10);
            },
            Key.COLS => {
                f_req.Cols = try std.fmt.parseInt(usize, kv.@"1", 10);
            },
            Key.VIEWPORT => {
                f_req.ViewPort = try std.fmt.allocPrint(allocator, "{s}", .{kv.@"1"});
            },
        }
    }
    if (f_req.Rows < 1 or f_req.Rows > 255) return error.InvalidDimensions;
    if (f_req.Cols < 3 or f_req.Cols > 255) return error.InvalidDimensions;
    return f_req;
}
