const std = @import("std");

pub fn Run(allocator: std.mem.Allocator, io: std.Io, baseDir: []const u8, viewport: []const u8) ![]const u8 {
    const viewportScript = try std.fmt.allocPrint(allocator, "{s}.sh", .{viewport});
    defer allocator.free(viewportScript);
    const path = try std.fs.path.join(allocator, &.{ baseDir, viewportScript });
    defer allocator.free(path);
    const result = try std.process.run(allocator, io, .{ .argv = &.{path} });
    defer allocator.free(result.stderr);
    return result.stdout;
}

test "sample_run" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;

    const output = try Run(gpa, io, "/home/tchaudhry/Workspace/netzfenster/examples", "disk");
    defer gpa.free(output);
    std.debug.print("{s}", .{output});
}
