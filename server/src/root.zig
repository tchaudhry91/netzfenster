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
};

pub const FrameSequence = struct {
    rows: u8,
    cols: u8,
    version: u8,
    frames: []Grid,
    fps: u8,
    refresh_ms: u32,
    viewport: []const u8,
};

test "writeText writes a string that fits and returns its length" {
    const gpa = std.testing.allocator;
    var g = try Grid.init(gpa, 8, 21);
    defer g.deinit(gpa);

    const n = g.writeText(0, 0, "HELLO");
    try std.testing.expectEqual(@as(usize, 5), n);
    try std.testing.expectEqual('H', g.cell(0, 0).char);
    try std.testing.expectEqual('E', g.cell(0, 1).char);
    try std.testing.expectEqual('L', g.cell(0, 2).char);
    try std.testing.expectEqual('L', g.cell(0, 3).char);
    try std.testing.expectEqual('O', g.cell(0, 4).char);
    try std.testing.expectEqual(' ', g.cell(0, 5).char);
}

test "writeText truncates at the right edge and returns the cutoff" {
    const gpa = std.testing.allocator;
    var g = try Grid.init(gpa, 2, 5);
    defer g.deinit(gpa);

    const n = g.writeText(0, 0, "ABCDEFG");
    try std.testing.expectEqual(@as(usize, 5), n);
    try std.testing.expectEqual('A', g.cell(0, 0).char);
    try std.testing.expectEqual('E', g.cell(0, 4).char);
    try std.testing.expectEqual(' ', g.cell(1, 0).char);
}

test "writeText composes to wrap a long message across rows" {
    const gpa = std.testing.allocator;
    var g = try Grid.init(gpa, 2, 5);
    defer g.deinit(gpa);

    const text = "ABCDEFGH";
    var i = g.writeText(0, 0, text);
    if (i < text.len) {
        i += g.writeText(1, 0, text[i..]);
    }
    try std.testing.expectEqual(@as(usize, text.len), i);
    try std.testing.expectEqual('A', g.cell(0, 0).char);
    try std.testing.expectEqual('E', g.cell(0, 4).char);
    try std.testing.expectEqual('F', g.cell(1, 0).char);
    try std.testing.expectEqual('H', g.cell(1, 2).char);
}
