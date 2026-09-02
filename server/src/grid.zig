const std = @import("std");

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

    /// Writes `line` to `row` starting at `col`, truncating at the right edge.
    ///
    /// Returns the number of characters written. If the whole string fits, this
    /// equals `line.len`; otherwise it is the index into `line` of the first
    /// character that did not fit. The caller can continue on the next row by
    /// passing `line[returned..]`.
    pub fn writeLine(self: *Grid, row: usize, col: usize, line: []const u8) usize {
        var cur: usize = 0;
        while ((cur + col < self.cols) and (cur < line.len)) : (cur += 1) {
            self.write(row, cur + col, line[cur]);
        }
        return cur;
    }

    /// Writes `text` to the grid starting at the top-left, wrapping long lines.
    ///
    /// Splits `text` on newlines and writes each line to a row. Lines longer than
    /// the grid width wrap to the next row with a 2-space indent. Writing stops
    /// when the grid is full.
    ///
    /// Returns the number of characters written. If the whole string fits, this
    /// equals `text.len`; otherwise it is the index into `text` of the first
    /// character that did not fit. The caller can resume by passing
    /// `text[returned..]`.
    pub fn writeText(self: *Grid, text: []const u8) usize {
        var curCol: usize = 0;
        var curRow: usize = 0;
        var lines = std.mem.splitScalar(u8, text, '\n');
        while (lines.next()) |line| {
            if (curRow >= self.rows) {
                return (line.ptr - text.ptr);
            }
            var ret = self.writeLine(curRow, curCol, line);
            curRow += 1;
            curCol = 2;
            while (ret != line.len) {
                if (curRow >= self.rows) {
                    return (line.ptr - text.ptr) + ret;
                }
                // Write the continuation lines if any
                ret += self.writeLine(curRow, curCol, line[ret..]);
                curRow += 1;
            }
            curCol = 0;
        }
        return text.len;
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

test "writeText writes multiple lines" {
    const gpa = std.testing.allocator;
    var g = try Grid.init(gpa, 3, 5);
    defer g.deinit(gpa);

    _ = g.writeText("HELLO\nWORLD");

    try std.testing.expectEqual('H', g.cell(0, 0).char);
    try std.testing.expectEqual('O', g.cell(0, 4).char);
    try std.testing.expectEqual('W', g.cell(1, 0).char);
    try std.testing.expectEqual('D', g.cell(1, 4).char);
    try std.testing.expectEqual(' ', g.cell(2, 0).char);
}

test "writeText wraps a long line with indent" {
    const gpa = std.testing.allocator;
    var g = try Grid.init(gpa, 3, 5);
    defer g.deinit(gpa);

    _ = g.writeText("HELLOWORLD");

    // row 0: "HELLO"
    try std.testing.expectEqual('H', g.cell(0, 0).char);
    try std.testing.expectEqual('O', g.cell(0, 4).char);
    // row 1: "  WOR" (2-space indent)
    try std.testing.expectEqual(' ', g.cell(1, 0).char);
    try std.testing.expectEqual(' ', g.cell(1, 1).char);
    try std.testing.expectEqual('W', g.cell(1, 2).char);
    try std.testing.expectEqual('R', g.cell(1, 4).char);
    // row 2: "  LD"
    try std.testing.expectEqual(' ', g.cell(2, 0).char);
    try std.testing.expectEqual(' ', g.cell(2, 1).char);
    try std.testing.expectEqual('L', g.cell(2, 2).char);
    try std.testing.expectEqual('D', g.cell(2, 3).char);
}

test "writeText returns the resume index" {
    const gpa = std.testing.allocator;

    // Everything fits: returns text.len.
    {
        var g = try Grid.init(gpa, 3, 5);
        defer g.deinit(gpa);
        try std.testing.expectEqual(@as(usize, 11), g.writeText("HELLO\nWORLD"));
    }

    // Stops mid-line: returns index of the first unwritten char.
    {
        var g = try Grid.init(gpa, 2, 5);
        defer g.deinit(gpa);
        try std.testing.expectEqual(@as(usize, 8), g.writeText("HELLOWORLD"));
    }

    // Stops at a fresh line: returns index of that line's start.
    {
        var g = try Grid.init(gpa, 3, 5);
        defer g.deinit(gpa);
        try std.testing.expectEqual(@as(usize, 6), g.writeText("A\nB\nC\nD"));
    }
}
