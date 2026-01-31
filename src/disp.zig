const std = @import("std");

pub fn clearAndPrint(comptime fmt: []const u8, args: anytype) void {
    var buf: [1024]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&buf);
    var stdout = &stdout_writer.interface;
    stdout.print("\x1b[2K", .{}) catch return;
    stdout.print(fmt, args) catch return;
    stdout.flush() catch unreachable;
    return;
}

pub inline fn fatal(comptime msg: []const u8) noreturn {
    fatalFmt(msg, .{});
}

pub fn fatalFmt(comptime fmt: []const u8, args: anytype) noreturn {
    var stderr_buf: [1024]u8 = undefined;
    var stderr_writer = std.fs.File.stderr().writer(&stderr_buf);
    var stderr = &stderr_writer.interface;
    stderr.print("\x1b[1;31mERROR:\x1b[0m ", .{}) catch unreachable;
    stderr.print(fmt, args) catch unreachable;
    stderr.flush() catch unreachable;
    std.process.exit(1);
}

pub fn printLoading(comptime msg: []const u8) void {
    clearAndPrint("{s}...\x1b[G", .{msg});
}
