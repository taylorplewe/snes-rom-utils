const std = @import("std");

pub fn main() void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    const args = std.process.argsAlloc(arena.allocator()) catch {
        printError("could not alloc args");
        return;
    };
    if (args.len < 2) printUsageAndExit();
    const infile = args[1];

    const rom_file = std.fs.cwd().openFile(infile, .{}) catch {
        printError("could not open file");
        return;
    };
    defer rom_file.close();
    var rom_reader = rom_file.reader();

    var checksum: u16 = 0;
    var file_len: u64 = 0;
    while (true) {
        checksum +%= rom_reader.readByte() catch break;
        file_len += 1;
    }

    std.debug.print("length: {d}\n", .{file_len});
    std.debug.print("checksum: {x}\n", .{checksum});
}

fn printError(msg: []const u8) void {
    std.io.getStdErr().writer().print("\x1b[1;31mERROR:\x1b[0m {s}\n", .{msg}) catch unreachable;
    std.process.exit(1);
}

fn printUsageAndExit() void {
    std.io.getStdOut().writer().print("\x1b[1;33mchecksum.exe:\x1b[0m pass in the path to your ROM file to fix the checksum.\n", .{}) catch unreachable;
    std.process.exit(0);
}
