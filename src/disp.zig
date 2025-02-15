const std = @import("std");

pub fn print(comptime msg: []const u8, args: anytype) void {
    std.io.getStdOut().writer().print("\x1b[2K", .{}) catch return;
    std.io.getStdOut().writer().print(msg, args) catch return;
    return;
}

pub fn printError(comptime msg: []const u8) void {
    std.io.getStdErr().writer().print("\x1b[1;31mERROR:\x1b[0m {s}\n", .{msg}) catch unreachable;
    std.process.exit(1);
}

pub fn printLoading(comptime msg: []const u8) void {
    print("{s}...\x1b[G", .{msg});
}
