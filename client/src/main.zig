const std = @import("std");
const Io = std.Io;

const log = std.log.scoped(.client);

const FrameData = struct {
    rows: [][]const u8,
    invert: [][]const u8,
};

const Frame = struct {
    version: u8,
    viewport: []const u8,
    cols: u8,
    rows: u8,
    refresh_ms: u32,
    frame_dwell_ms: u32,
    frames: []FrameData,
};

pub fn main(init: std.process.Init) !void {
    const gpa = std.heap.page_allocator;
    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();
    const allocator = arena.allocator();

    const io = init.io;

    const args = try init.minimal.args.toSlice(allocator);
    if (args.len < 2) {
        log.err("usage: {s} <viewport> [server_addr] [rows] [cols]", .{args[0]});
        return error.MissingViewport;
    }
    const viewport = args[1];
    const server_addr = if (args.len > 2) args[2] else "127.0.0.1:8989";
    const rows = if (args.len > 3) try std.fmt.parseInt(u8, args[3], 10) else 8;
    const cols = if (args.len > 4) try std.fmt.parseInt(u8, args[4], 10) else 21;

    const url = try std.fmt.allocPrint(allocator, "http://{s}/frame?viewport={s}&rows={d}&cols={d}", .{ server_addr, viewport, rows, cols });
    log.info("polling {s}", .{url});

    var client: std.http.Client = .{ .allocator = gpa, .io = io };
    defer client.deinit();

    var stdout_buffer: [4096]u8 = undefined;
    var stdout_file_writer: Io.File.Writer = .init(.stdout(), io, &stdout_buffer);
    const stdout_writer = &stdout_file_writer.interface;

    while (true) {
        var poll_arena = std.heap.ArenaAllocator.init(gpa);
        defer poll_arena.deinit();
        const pa = poll_arena.allocator();

        const frame = fetchFrame(&client, pa, url) catch |err| {
            log.err("fetch failed: {any}", .{err});
            try sleepMs(io, 1000);
            continue;
        };

        for (frame.frames, 0..) |f, i| {
            try renderFrameData(stdout_writer, f);
            if (i + 1 < frame.frames.len) {
                try sleepMs(io, frame.frame_dwell_ms);
            }
        }
        try sleepMs(io, frame.refresh_ms);
    }
}

fn fetchFrame(client: *std.http.Client, allocator: std.mem.Allocator, url: []const u8) !Frame {
    var aw = std.Io.Writer.Allocating.init(allocator);
    defer aw.deinit();
    const result = try client.fetch(.{
        .location = .{ .url = url },
        .response_writer = &aw.writer,
        .keep_alive = false,
    });
    if (result.status != .ok) {
        log.err("server returned {s}", .{@tagName(result.status)});
        return error.HttpError;
    }
    const body = aw.writer.buffer[0..aw.writer.end];
    return try std.json.parseFromSliceLeaky(Frame, allocator, body, .{});
}

fn renderFrameData(w: *Io.Writer, f: FrameData) !void {
    try w.writeAll("\x1b[2J\x1b[H");
    for (f.rows, 0..) |row, r| {
        const inv = f.invert[r];
        var inverted = false;
        for (row, 0..) |ch, c| {
            const want_invert = inv[c] == '1';
            if (want_invert != inverted) {
                try w.writeAll(if (want_invert) "\x1b[7m" else "\x1b[0m");
                inverted = want_invert;
            }
            try w.writeByte(ch);
        }
        if (inverted) try w.writeAll("\x1b[0m");
        try w.writeByte('\n');
    }
    try w.flush();
}

fn sleepMs(io: std.Io, ms: u32) !void {
    try std.Io.sleep(io, std.Io.Duration.fromMilliseconds(@intCast(ms)), .awake);
}
