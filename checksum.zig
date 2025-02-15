const std = @import("std");

var header_addr: u24 = 0x007fc0;
const possible_header_addrs: []const u24 = &[_]u24{
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

    const rom_file = std.fs.cwd().openFile(infile, .{ .mode = .read_write }) catch {
        printError("could not open file");
        return;
    };
    defer rom_file.close();
    var rom_reader = rom_file.reader();

    var checksum: u16 = 0;
    var file_len: u64 = 0;

    // calculate checksum
    printLoading("calculating checksum");
    while (true) {
        checksum +%= rom_reader.readByte() catch break;
        file_len += 1;
    }
    print("checksum: \x1b[33m0x{x}\x1b[0m\n", .{checksum});

    // write checksum to ROM header
    printLoading("writing checksum to ROM header");
    const buf = arena.allocator().alloc(u8, 32) catch {
        printError("could not alloc header buffer");
        return;
    };
    var isHeaderFound = false;
    for (possible_header_addrs) |addr| {
        rom_file.seekTo(addr) catch {
            printError("could not seek file");
            continue;
        };
        _ = rom_reader.read(buf) catch {
            printError("could not read file into buffer");
            continue;
        };
        if (checkForHeader(buf)) {
            const writer = rom_file.writer();
            rom_file.seekTo(addr + 0x1c) catch {
                printError("could not seek file for writing");
                return;
            };
            writer.writeInt(u16, checksum ^ 0xffff, std.builtin.Endian.little) catch {
                printError("could not write to file");
                return;
            };
            writer.writeInt(u16, checksum, std.builtin.Endian.little) catch {
                printError("could not write to file");
                return;
            };
            print("\x1b[32mchecksum written to ROM header.\x1b[0m", .{});
            isHeaderFound = true;
            break;
        }
    }
    if (!isHeaderFound) printError("could not find header in ROM\n  a ROM header must meet the criteria as described at \x1b]8;;https://snes.nesdev.org/wiki/ROM_header\x1b\\https://snes.nesdev.org/wiki/ROM_header\x1b]8;;\x1b\\");
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
    const hardware = memory[0x16];
    if (hardware != 0 and hardware != 1 and hardware != 2) {
        if ((hardware & 0x0f) > 6) return false;
        if ((hardware >> 4) > 0x5 and (hardware >> 4) < 0xe) return false;
    }

    // existing checksum & complement
    if (memory[0x1c] ^ memory[0x1e] != 0xff or memory[0x1d] ^ memory[0x1f] != 0xff) return false;

    return true;
}

fn printError(comptime msg: []const u8) void {
    std.io.getStdErr().writer().print("\x1b[1;31mERROR:\x1b[0m {s}\n", .{msg}) catch unreachable;
    std.process.exit(1);
}

fn print(comptime msg: []const u8, args: anytype) void {
    std.io.getStdOut().writer().print("\x1b[2K", .{}) catch return;
    std.io.getStdOut().writer().print(msg, args) catch return;
    return;
}

fn printLoading(comptime msg: []const u8) void {
    print("{s}...\x1b[G", .{msg});
}

fn printUsageAndExit() void {
    std.io.getStdOut().writer().print("\x1b[1;33mchecksum.exe:\x1b[0m pass in the path to your ROM file to fix the checksum.\n", .{}) catch unreachable;
    std.process.exit(0);
}
