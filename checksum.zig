const std = @import("std");

var header_addr: u24 = 0x007fc0;
const possible_header_addrs: []const u24 = [_]u24{
    0x007fc0,
    0x00ffc0,
    0x40ffc0,
};
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

    // now place header in rom
    rom_file.seekTo(0x7fc0) catch {
        printError("could not seek file");
        return;
    };
    const buf = arena.allocator().alloc(u8, 32) catch {
        printError("could not alloc header buffer");
        return;
    };
    _ = rom_reader.read(buf) catch {
        printError("could not read file into buffer");
        return;
    };
    const isHeader = checkForHeader(buf);
    std.debug.print("{}\n", .{isHeader});
}

fn printError(msg: []const u8) void {
    std.io.getStdErr().writer().print("\x1b[1;31mERROR:\x1b[0m {s}\n", .{msg}) catch unreachable;
    std.process.exit(1);
}

fn printUsageAndExit() void {
    std.io.getStdOut().writer().print("\x1b[1;33mchecksum.exe:\x1b[0m pass in the path to your ROM file to fix the checksum.\n", .{}) catch unreachable;
    std.process.exit(0);
}

fn checkForHeader(memory: []u8) bool {
    // ascii name of ROM
    for (memory[0..0x15]) |byte| {
        if (!std.ascii.isAlphabetic(byte) and !std.ascii.isWhitespace(byte) and byte != 0)
            return false;
    }

    // mapper mode byte
    if (memory[0x15] & 0b11100000 != 0b00100000) return false;
    const map_mode = memory[0x15] & 0x0f;
    if (map_mode != 0 and map_mode != 1 and map_mode != 5) return false;

    // hardware info byte

    return true;
}
