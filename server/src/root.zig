const std = @import("std");
pub const grid = @import("grid.zig");
pub const frame = @import("frame.zig");
pub const view = @import("view.zig");

pub const Cell = grid.Cell;
pub const Grid = grid.Grid;
pub const FrameSequence = frame.FrameSequence;

pub const Config = struct { base_dir_path: []const u8, listen_addr: []const u8 };

pub fn serializeViewPort(allocator: std.mem.Allocator, io: std.Io, name: []const u8, conf: Config, rows: u8, cols: u8) ![]const u8 {
    if (rows == 0 or cols == 0) {
        return error.InvalidDimensions;
    }
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const aa = arena.allocator();

    var vp = try view.ViewPort.init(aa, io, conf.base_dir_path, name);
    const vp_data = try vp.run(aa, io);

    var fs = FrameSequence{ .rows = rows, .cols = cols, .version = 1, .refresh_ms = vp.refresh_ms, .viewport = name, .frame_dwell_ms = 3000, .frames = undefined };

    var frames = try std.ArrayList(Grid).initCapacity(aa, 1);
    var written: usize = 0;
    while (written < vp_data.len) {
        var g = try Grid.init(aa, rows, cols);
        written += g.writeText(vp_data[written..]);
        try frames.append(aa, g);
    }

    if (frames.items.len == 0) {
        // Add an empty frame incase the script gave no output.
        try frames.append(aa, try Grid.init(aa, rows, cols));
    }

    fs.frames = frames.items;

    return try std.json.Stringify.valueAlloc(allocator, fs, .{});
}

fn fixturesDir(allocator: std.mem.Allocator, io: std.Io) ![]const u8 {
    const cwd: []const u8 = try std.process.currentPathAlloc(io, allocator);
    defer allocator.free(cwd);
    return std.fs.path.resolve(allocator, &.{ cwd, "test", "fixtures" });
}

test "serializeViewPort returns a valid frame sequence" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const aa = arena.allocator();
    const io = std.testing.io;

    const conf = Config{
        .base_dir_path = try fixturesDir(aa, io),
        .listen_addr = "127.0.0.1:8080",
    };

    const json = try serializeViewPort(aa, io, "hello", conf, 8, 21);

    var parsed = try std.json.parseFromSlice(std.json.Value, aa, json, .{});
    defer parsed.deinit();

    const obj = switch (parsed.value) {
        .object => |o| o,
        else => return error.TestUnexpectedResult,
    };

    try std.testing.expectEqual(@as(i64, 1), obj.get("version").?.integer);
    try std.testing.expectEqualStrings("hello", obj.get("viewport").?.string);
    try std.testing.expectEqual(@as(i64, 21), obj.get("cols").?.integer);
    try std.testing.expectEqual(@as(i64, 8), obj.get("rows").?.integer);

    const frames = switch (obj.get("frames").?) {
        .array => |a| a,
        else => return error.TestUnexpectedResult,
    };
    try std.testing.expectEqual(@as(usize, 1), frames.items.len);

    const first_frame = switch (frames.items[0]) {
        .object => |o| o,
        else => return error.TestUnexpectedResult,
    };
    const rows = switch (first_frame.get("rows").?) {
        .array => |a| a,
        else => return error.TestUnexpectedResult,
    };
    try std.testing.expectEqual(@as(usize, 8), rows.items.len);
    try std.testing.expect(std.mem.startsWith(u8, rows.items[0].string, "HELLO"));
    try std.testing.expect(std.mem.startsWith(u8, rows.items[1].string, "WORLD"));
}

test "serializeViewPort paginates long output across frames" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const aa = arena.allocator();
    const io = std.testing.io;

    const conf = Config{
        .base_dir_path = try fixturesDir(aa, io),
        .listen_addr = "127.0.0.1:8080",
    };

    const json = try serializeViewPort(aa, io, "alphabet", conf, 2, 5);

    var parsed = try std.json.parseFromSlice(std.json.Value, aa, json, .{});
    defer parsed.deinit();

    const obj = switch (parsed.value) {
        .object => |o| o,
        else => return error.TestUnexpectedResult,
    };

    const frames = switch (obj.get("frames").?) {
        .array => |a| a,
        else => return error.TestUnexpectedResult,
    };
    try std.testing.expectEqual(@as(usize, 3), frames.items.len);

    const expected = [_][]const u8{ "A", "B", "C", "D", "E", "F" };
    var i: usize = 0;
    for (frames.items) |frame_val| {
        const frame_obj = switch (frame_val) {
            .object => |o| o,
            else => return error.TestUnexpectedResult,
        };
        const rows = switch (frame_obj.get("rows").?) {
            .array => |a| a,
            else => return error.TestUnexpectedResult,
        };
        try std.testing.expectEqual(@as(usize, 2), rows.items.len);
        for (rows.items) |row| {
            try std.testing.expectEqual(@as(usize, 5), row.string.len);
            try std.testing.expect(std.mem.startsWith(u8, row.string, expected[i]));
            i += 1;
        }
    }
    try std.testing.expectEqual(@as(usize, 6), i);
}
