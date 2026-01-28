const std = @import("std");
const disp = @import("disp.zig");
const fatal = disp.fatal;
const info = @import("info.zig");
const checksum = @import("checksum.zig");
const split = @import("split.zig");
const patch = @import("patch/patch.zig");

pub fn main() void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    const args = std.process.argsAlloc(arena.allocator()) catch fatal("unable to allocate memory for arguments", .{});
    if (args.len < 3) printUsageAndExit();

    const util_name = args[1];
    const rom_path = args[2];

    const rom_file = std.fs.cwd().openFile(rom_path, .{ .mode = .read_write }) catch fatal("could not open file \x1b[1m{s}\x1b[0m", .{rom_path});

    if (std.mem.eql(u8, util_name, "info")) {
        info.displayInfo();
    } else if (std.mem.eql(u8, util_name, "fix-checksum")) {
        checksum.fixChecksum(rom_file);
    } else if (std.mem.eql(u8, util_name, "split")) {
        split.split(arena.allocator(), rom_file, rom_path);
    } else if (std.mem.eql(u8, util_name, "patch")) {
        patch.patch(arena.allocator(), args[2..]);
    } else {
        fatal("util with the name \x1b[1m{s}\x1b[0m not found", .{util_name});
    }
}

fn printUsageAndExit() noreturn {
    disp.clearAndPrint("\x1b[1;33msnestils.exe:\x1b[0m modify an SNES ROM\n" ++
        "usage: \x1b[34msnestils <util> <path-to-rom>\x1b[0m\n" ++
        "  \x1b[34m<util> \x1b[0m=\n" ++
        "    \x1b[33minfo\x1b[0m - print out all the information about a ROM according to its header\n" ++
        "    \x1b[33mfix-checksum\x1b[0m - calculate the ROM's correct checksum and write it to the ROM's header\n" ++
        "    \x1b[33msplit\x1b[0m - repeat a ROM's contents to fill a certain amount of memory\n" ++
        "    \x1b[33mpatch\x1b[0m - apply an IPS patch file to a ROM\n" ++
        "    \x1b[33mremove-header\x1b[0m - remove a ROM's header\n", .{});
    std.process.exit(0);
}
