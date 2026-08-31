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
