const std = @import("std");
const disp = @import("disp.zig");
const fatal = disp.fatal;

pub fn split(allocator: std.mem.Allocator, rom_file: std.fs.File, rom_file_path: []const u8) void {
    // get size in KiB from user
    var targ_size_input: []u8 = undefined;
    var targ_size: u64 = 0;
    while (true) {
        var reader_buf: [1024]u8 = undefined;
        var stdin_core = std.fs.File.stdin().reader(&reader_buf);
        var stdin = &stdin_core.interface;

        disp.clearAndPrint("What size KiB chunks (512, 1024, or 2048)? ", .{});
        targ_size_input = stdin.takeDelimiter('\n') catch fatal("could not read input from user", .{}) orelse &.{};
        targ_size = std.fmt.parseInt(u64, std.mem.trimRight(u8, targ_size_input, "\n\r"), 10) catch {
            disp.clearAndPrint("please provide a numeric value!\n", .{});
            continue;
        };
        if (targ_size == 512 or targ_size == 1024 or targ_size == 2048) break;
        disp.clearAndPrint("please provide a valid KiB size!\n", .{});
    }
    targ_size *= 1024; // KiB

    // get file size
    rom_file.seekFromEnd(0) catch unreachable;
    var remaining_size = rom_file.getPos() catch fatal("could not get size of file", .{});
    if (remaining_size < targ_size) {
        disp.clearAndPrint("ROM file is already smaller or equal to {d} bytes!", .{targ_size});
        std.process.exit(0);
    }

    // write split files
    rom_file.seekTo(0) catch unreachable;
    const buf = allocator.alloc(u8, targ_size) catch fatal("could not allocate buffer", .{});
    var iter: u8 = 0;

    // separate rom file extension from main part
    const last_index_of_period = if (std.mem.lastIndexOfScalar(u8, rom_file_path, '.')) |idx| idx else rom_file_path.len;
    const rom_file_name_base = rom_file_path[0..last_index_of_period];
    const rom_file_ext = rom_file_path[last_index_of_period..];

    while (remaining_size > 0) : (remaining_size -= targ_size) {
        const split_file_path = std.fmt.allocPrint(allocator, "{s}_{d:0>2}{s}", .{ rom_file_name_base, iter, rom_file_ext }) catch unreachable;
        const split_file = std.fs.cwd().createFile(split_file_path, .{}) catch
            fatal("could not create split file", .{});
        defer split_file.close();
        _ = rom_file.read(buf) catch fatal("could not read ROM file into split buffer", .{});
        _ = split_file.write(buf) catch fatal("could not write split buffer into split file", .{});
        iter += 1;
    }
    disp.clearAndPrint("\x1b[32msplit ROM files written to same directory as given ROM file.\x1b[0m", .{});
}
