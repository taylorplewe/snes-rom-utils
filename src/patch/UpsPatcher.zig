const std = @import("std");
const disp = @import("../disp.zig");
const fatal = disp.fatal;
const Patcher = @import("./Patcher.zig");

const UpsPatcher = @This();

pub fn init(
    allocator: *const std.mem.Allocator,
    patch_file_reader: *std.fs.File.Reader,
    original_rom_file_reader: *std.fs.File.Reader,
    patched_rom_file_writer: *std.fs.File.Writer,
) Patcher {
    return .{
        .vtable = &.{
            .validate = UpsPatcher.validate,
            .apply = UpsPatcher.apply,
        },
        .allocator = allocator,
        .patch_file_reader = patch_file_reader,
        .original_rom_file_reader = original_rom_file_reader,
        .patched_rom_file_writer = patched_rom_file_writer,
    };
}

fn validate(self: *Patcher) void {
    if (!std.mem.eql(u8, self.patchReader().peekArray(4) catch "", "UPS1")) {
        fatal("UPS patch files must begin with the word \"UPS1\"", .{});
    }
    self.patch_file_reader.seekTo(4) catch fatal("could not seek patch file", .{});
    const expected_size_original_rom = takeVariableWidthInteger(self);
    const original_rom_file_len = self.original_rom_file_reader.getSize() catch fatal("could not get original ROM file size", .{});
    if (expected_size_original_rom != original_rom_file_len) {
        fatal("original ROM file size does not match expected size.\n  expected size: {d}\n  actual size: {d}\n", .{ expected_size_original_rom, original_rom_file_len });
    } else {
        disp.clearAndPrint("\x1b[32moriginal ROM file size matches expected size (\x1b[0;1m{d}\x1b[0;32m)\x1b[0m\n", .{expected_size_original_rom});
    }
}

fn apply(self: *Patcher) void {
    const expected_size_patched_rom = takeVariableWidthInteger(self); // size of patched ROM file

    const patch_file_len = self.patch_file_reader.getSize() catch fatal("could not get patch file size", .{});
    const original_rom_file_len = self.original_rom_file_reader.getSize() catch fatal("could not get original ROM file size", .{});
    while (self.patch_file_reader.logicalPos() < patch_file_len - 12) {
        const bytes_to_skip = takeVariableWidthInteger(self);
        if (bytes_to_skip > 0) {
            if (self.original_rom_file_reader.logicalPos() >= original_rom_file_len) {
                _ = self.patchedRomWriter().splatByteAll(0, bytes_to_skip) catch fatal("could not write 0s to patched ROM file", .{});
            } else {
                self.original_rom_file_reader.seekBy(@intCast(bytes_to_skip)) catch fatal("could not seek original ROM file", .{});
                self.patchedRomWriter().flush() catch fatal("could not flush patched ROM file prior to seek", .{});
                self.patched_rom_file_writer.seekTo(self.original_rom_file_reader.logicalPos()) catch fatal("could not seek patched ROM file", .{});
            }
        }

        var patch_byte_to_xor = self.patchReader().takeByte() catch fatal("could not read XOR byte from patch file", .{});
        while (patch_byte_to_xor != 0) {
            const byte_to_write = patch_byte_to_xor ^
                if (self.original_rom_file_reader.logicalPos() >= original_rom_file_len)
                    0
                else
                    self.originalRomReader().takeByte() catch fatal("could not read byte from original ROM file", .{});
            self.patchedRomWriter().writeByte(byte_to_write) catch fatal("could not write XOR'd byte to patched ROM file", .{});
            patch_byte_to_xor = self.patchReader().takeByte() catch fatal("could not read XOR byte from patch file", .{});
        }

        if (self.patch_file_reader.logicalPos() < patch_file_len - 12) {
            if (self.original_rom_file_reader.logicalPos() >= original_rom_file_len) {
                self.patchedRomWriter().writeByte(0) catch fatal("could not write 0 to patched ROM file", .{});
            } else {
                self.originalRomReader().discardAll(1) catch fatal("could not discard byte from original ROM file", .{});
                self.patchedRomWriter().flush() catch fatal("could not flush patched ROM file prior to seek", .{});
                self.patched_rom_file_writer.seekTo(self.original_rom_file_reader.logicalPos()) catch fatal("could not seek patched ROM file", .{});
            }
        }
    }
    self.patchedRomWriter().flush() catch fatal("could not flush patched ROM file", .{});

    // validate patched ROM size
    const patched_rom_file_len = self.patched_rom_file_writer.pos;
    if (patched_rom_file_len != expected_size_patched_rom) {
        fatal("final patched ROM file size does not match expected size.\n  expected size: {d}\n  actual size: {d}\n", .{ expected_size_patched_rom, patched_rom_file_len });
    } else {
        disp.clearAndPrint("\x1b[32mfinal patched ROM file size matches expected size (\x1b[0;1m{d}\x1b[0;32m)\x1b[0m\n", .{expected_size_patched_rom});
    }
}

fn takeVariableWidthInteger(self: *Patcher) usize {
    var result: usize = 0;
    var shift: u6 = 0;

    while (true) {
        const byte = self.patchReader().takeByte() catch fatal("could not read byte from patch file", .{});
        if ((byte & 0x80) != 0) {
            result += @as(usize, byte & 0x7f) << shift;
            break;
        }
        result += @as(usize, byte | 0x80) << shift;
        shift += 7;
    }

    return result;
}

fn calcCrc32(data: []const u8) u32 {
    var crc32: u32 = 0xffffffff;
    for (data) |byte| {
        crc32 ^= byte;
        crc32 = (crc32 >> 8) ^ crc32_table[crc32 & 0xff];
    }
    return ~crc32;
}

test calcCrc32 {
    try std.testing.expectEqual(0x8587D865, calcCrc32("abcde"));
    try std.testing.expectEqual(0x0f5cc4b4, calcCrc32(&[_]u8{ 0xf3, 0x85, 0x9a, 0x84, 0xfc, 0x24, 0xde, 0x22 }));
}

pub const crc32_table = blk: {
    var table: [256]u32 = undefined;
    table[0] = 0;

    var crc32: u32 = 1;
    var i: usize = 128;
    while (i != 0) : (i >>= 1) {
        crc32 = (crc32 >> 1) ^ (if ((crc32 & 1) != 0) 0xedb88320 else 0);
        var j: usize = 0;
        while (j < 256) : (j += 2 * i) {
            table[i + j] = crc32 ^ table[j];
        }
    }

    break :blk table;
};

test crc32_table {
    try std.testing.expectEqual(crc32_table[0], 0);
    try std.testing.expectEqual(crc32_table[1], 0x77073096);
    try std.testing.expectEqual(crc32_table[2], 0xee0e612c);
    try std.testing.expectEqual(crc32_table[255], 0x02d02ef8d);
}
