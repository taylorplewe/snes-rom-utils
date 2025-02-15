const std = @import("std");
const disp = @import("disp.zig");

const possible_header_addrs: []const u24 = &[_]u24{
    0x007fc0,
    0x00ffc0,
    0x40ffc0,
};
pub fn fixChecksum(allocator: std.mem.Allocator, rom_file: std.fs.File) void {
    var rom_reader = rom_file.reader();

    var checksum: u16 = 0;
    var file_len: u64 = 0;

    // calculate checksum
    disp.printLoading("calculating checksum");
    while (true) {
        checksum +%= rom_reader.readByte() catch break;
        file_len += 1;
    }
    disp.print("checksum: \x1b[33m0x{x}\x1b[0m\n", .{checksum});

    // write checksum to ROM header
    disp.printLoading("writing checksum to ROM header");
    const buf = allocator.alloc(u8, 32) catch {
        disp.printError("could not alloc header buffer");
        return;
    };
    for (possible_header_addrs) |addr| {
        rom_file.seekTo(addr) catch {
            disp.printError("could not seek file");
            continue;
        };
        _ = rom_reader.read(buf) catch {
            disp.printError("could not read file into buffer");
            continue;
        };
        if (checkForHeader(buf)) {
            const writer = rom_file.writer();
            rom_file.seekTo(addr + 0x1c) catch {
                disp.printError("could not seek file for writing");
                return;
            };
            writer.writeInt(u16, checksum ^ 0xffff, std.builtin.Endian.little) catch {
                disp.printError("could not write to file");
                return;
            };
            writer.writeInt(u16, checksum, std.builtin.Endian.little) catch {
                disp.printError("could not write to file");
                return;
            };
            disp.print("\x1b[32mchecksum written to ROM header.\x1b[0m", .{});
            return;
        }
    }
    disp.printError("could not find header in ROM\n  a ROM header must meet the criteria as described at \x1b]8;;https://snes.nesdev.org/wiki/ROM_header\x1b\\https://snes.nesdev.org/wiki/ROM_header\x1b]8;;\x1b\\");
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
