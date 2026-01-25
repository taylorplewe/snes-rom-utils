const std = @import("std");

pub fn print(comptime msg: []const u8, args: anytype) void {
    var buf: [1024]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&buf);
    var stdout = &stdout_writer.interface;
    stdout.print("\x1b[2K", .{}) catch return;
    stdout.print(msg, args) catch return;
    stdout.flush() catch unreachable;
    return;
}

pub fn printErrorAndExit(comptime msg: []const u8) void {
    var buf: [1024]u8 = undefined;
    var stderr_writer = std.fs.File.stderr().writer(&buf);
    var stderr = &stderr_writer.interface;
    stderr.print("\x1b[1;31mERROR:\x1b[0m {s}\n", .{msg}) catch unreachable;
    stderr.flush() catch unreachable;
    std.process.exit(1);
}

pub fn printLoading(comptime msg: []const u8) void {
    print("{s}...\x1b[G", .{msg});
}
