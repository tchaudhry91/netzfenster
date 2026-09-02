const std = @import("std");
const grid = @import("grid.zig");
const Grid = grid.Grid;

pub const FrameSequence = struct {
    rows: u8,
    cols: u8,
    version: u8,
    frames: []Grid,
    refresh_ms: u32,
    frame_dwell_ms: u32,
    viewport: []const u8,
};

test "serialize a frame sequence to JSON" {
    const gpa = std.testing.allocator;

    var frames: [2]Grid = undefined;
    frames[0] = try Grid.init(gpa, 3, 5);
    frames[1] = try Grid.init(gpa, 3, 5);
    defer frames[0].deinit(gpa);
    defer frames[1].deinit(gpa);

    _ = frames[0].writeLine(0, 0, "HELLO");
    frames[0].cell(0, 0).invert = true;
    _ = frames[1].writeLine(0, 0, "WORLD");

    const seq = FrameSequence{
        .rows = 3,
        .cols = 5,
        .version = 1,
        .frames = &frames,
        .refresh_ms = 30000,
        .frame_dwell_ms = 500,
        .viewport = "planes",
    };

    const json = try std.json.Stringify.valueAlloc(gpa, seq, .{});
    defer gpa.free(json);

    try std.testing.expectEqualStrings(
        "{\"rows\":3,\"cols\":5,\"version\":1,\"frames\":[{\"rows\":[\"HELLO\",\"     \",\"     \"],\"invert\":[\"10000\",\"00000\",\"00000\"]},{\"rows\":[\"WORLD\",\"     \",\"     \"],\"invert\":[\"00000\",\"00000\",\"00000\"]}],\"refresh_ms\":30000,\"frame_dwell_ms\":500,\"viewport\":\"planes\"}",
        json,
    );
}
