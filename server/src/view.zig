const std = @import("std");

pub const ViewPort = struct {
    cmd: []const u8,
    refresh_ms: u32 = 1000,
    base_dir: []const u8 = "",

    pub fn init(arena: std.mem.Allocator, io: std.Io, base_dir_path: []const u8, name: []const u8) !ViewPort {
        const base_dir = try std.Io.Dir.openDirAbsolute(io, base_dir_path, .{ .follow_symlinks = true, .access_sub_paths = true });
        defer base_dir.close(io);
        const viewport_file = try std.fs.path.join(arena, &.{ base_dir_path, try std.fmt.allocPrint(arena, "{s}.json", .{name}) });
        const viewport_data = try base_dir.readFileAlloc(io, viewport_file, arena, .unlimited);
        var vw = try std.json.parseFromSliceLeaky(ViewPort, arena, viewport_data, .{ .ignore_unknown_fields = true });
        vw.base_dir = try std.fmt.allocPrint(arena, "{s}", .{base_dir_path});
        return vw;
    }

    pub fn run(self: *ViewPort, arena: std.mem.Allocator, io: std.Io) ![]const u8 {
        const result = try std.process.run(arena, io, .{ .argv = &.{ "sh", "-c", self.cmd }, .cwd = .{ .path = self.base_dir } });
        return result.stdout;
    }
};
