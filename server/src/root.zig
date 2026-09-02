//! By convention, root.zig is the root source file when making a package.
const std = @import("std");
const Io = std.Io;

pub const Cell = struct {
    char: u8,
    invert: bool,
};

pub const Grid = struct {
    rows: usize,
    cols: usize,
    cells: []Cell,

    pub fn init(allocator: std.mem.Allocator, rows: usize, cols: usize) !Grid {
        const cells = try allocator.alloc(Cell, rows * cols);
        @memset(cells, .{ .char = ' ', .invert = false });
        return .{ .rows = rows, .cols = cols, .cells = cells };
    }

    pub fn deinit(self: *Grid, allocator: std.mem.Allocator) void {
        allocator.free(self.cells);
        self.* = undefined;
    }

    pub fn cell(self: *Grid, row: usize, col: usize) *Cell {
        std.debug.assert(row < self.rows and col < self.cols);
        return &self.cells[row * self.cols + col];
    }

    pub fn clear(self: *Grid) void {
        @memset(self.cells, .{ .char = ' ', .invert = false });
    }

    pub fn write(self: *Grid, row: usize, col: usize, char: u8) void {
        std.debug.assert(row < self.rows and col < self.cols);
        self.cell(row, col).char = char;
    }

    /// Writes `text` to `row` starting at `col`, truncating at the right edge.
    ///
    /// Returns the number of characters written. If the whole string fits, this
    /// equals `text.len`; otherwise it is the index into `text` of the first
    /// character that did not fit. The caller can continue on the next row by
    /// passing `text[returned..]`.
    pub fn writeText(self: *Grid, row: usize, col: usize, text: []const u8) usize {
        var cur: usize = 0;
        while ((cur + col < self.cols) and (cur < text.len)) : (cur += 1) {
            self.write(row, cur + col, text[cur]);
        }
        return cur;
    }

    pub fn jsonStringify(self: @This(), jw: anytype) !void {
        var buf: [256]u8 = @splat(' ');
        std.debug.assert(self.cols < buf.len);

        try jw.beginObject();
        try jw.objectField("rows");
        try jw.beginArray();
        for (0..self.rows) |row| {
            for (0..self.cols) |col| {
                buf[col] = self.cells[row * self.cols + col].char;
            }
            try jw.write(buf[0..self.cols]);
        }
        try jw.endArray();
        try jw.objectField("invert");
        try jw.beginArray();
        for (0..self.rows) |row| {
            buf = @splat('0');
            for (0..self.cols) |col| {
                if (self.cells[row * self.cols + col].invert) buf[col] = '1';
            }
            try jw.write(buf[0..self.cols]);
        }
        try jw.endArray();
        try jw.endObject();
    }
};

pub const FrameSequence = struct {
    rows: u8,
    cols: u8,
    version: u8,
    frame: Grid,
    refresh_ms: u32,
    viewport: []const u8,
};

test "serialize a frame to JSON" {
    const gpa = std.testing.allocator;

    var frame = try Grid.init(gpa, 3, 5);
    defer frame.deinit(gpa);

    _ = frame.writeText(0, 0, "HELLO");
    frame.cell(0, 0).invert = true;

    const seq = FrameSequence{
        .rows = 3,
        .cols = 5,
        .version = 1,
        .frame = frame,
        .refresh_ms = 30000,
        .viewport = "planes",
    };

    const json = try std.json.Stringify.valueAlloc(gpa, seq, .{});
    defer gpa.free(json);

    try std.testing.expectEqualStrings(
        "{\"rows\":3,\"cols\":5,\"version\":1,\"frame\":{\"rows\":[\"HELLO\",\"     \",\"     \"],\"invert\":[\"10000\",\"00000\",\"00000\"]},\"refresh_ms\":30000,\"viewport\":\"planes\"}",
        json,
    );
}
