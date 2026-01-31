// the BPS patch file format documentation I used can be found here: http://justsolve.archiveteam.org/wiki/UPS_(binary_patch_format)

const std = @import("std");
const disp = @import("../disp.zig");
const fatal = disp.fatal;
const Patcher = @import("./Patcher.zig");

const BpsPatcher = @This();

pub fn init(
    allocator: *const std.mem.Allocator,
    patch_file_reader: *std.fs.File.Reader,
    original_rom_file_reader: *std.fs.File.Reader,
    patched_rom_file_writer: *std.fs.File.Writer,
) Patcher {
    return .{
        .vtable = &.{
            .validate = BpsPatcher.validate,
            .apply = BpsPatcher.apply,
        },
        .allocator = allocator,
        .patch_file_reader = patch_file_reader,
        .original_rom_file_reader = original_rom_file_reader,
        .patched_rom_file_writer = patched_rom_file_writer,
    };
}

// TODO: might just reference UpsPatcher.validate instead of copying it here
fn validate(self: *Patcher) void {
    // "BPS1" string
    if (!std.mem.eql(u8, self.patchReader().peekArray(4) catch "", "BPS1")) {
        fatal("UPS patch files must begin with the word \"UPS1\"", .{});
    }

    // original ROM checksum
    const patch_file_size = self.patch_file_reader.getSize() catch fatal("could not get size of patch file", .{});
    self.patch_file_reader.seekTo(patch_file_size - 12) catch fatal("could not seek to original ROM checksum in patch file", .{});
    {
        const checksum_expected = self.patchReader().takeInt(u32, .little) catch fatal("could not get original ROM checksum in patch file", .{});
        const checksum_actual = calcCrc32FromFileReader(self.original_rom_file_reader, null);
        if (checksum_expected != checksum_actual) {
            fatal("original ROM checksum does not match calculated checksum\n  expected: 0x{x:0>8}\n  actual: 0x{x:0>8}\n", .{ checksum_expected, checksum_actual });
        } else {
            disp.clearAndPrint("\x1b[32moriginal ROM checksum matches calculated checksum (\x1b[0;1m0x{x:0>8}\x1b[0;32m)\x1b[0m\n", .{checksum_actual});
        }
    }

    // patch file checksum
    self.patch_file_reader.seekTo(patch_file_size - 4) catch fatal("could not seek to final checksum in patch file", .{});
    {
        const checksum_expected = self.patchReader().takeInt(u32, .little) catch fatal("could not get final checksum in patch file", .{});
        const checksum_actual = calcCrc32FromFileReader(self.patch_file_reader, patch_file_size - 4);
        if (checksum_expected != checksum_actual) {
            fatal("patch file checksum does not match calculated checksum\n  expected: 0x{x:0>8}\n  actual: 0x{x:0>8}\n", .{ checksum_expected, checksum_actual });
        } else {
            disp.clearAndPrint("\x1b[32mpatch file checksum matches calculated checksum (\x1b[0;1m0x{x:0>8}\x1b[0;32m)\x1b[0m\n", .{checksum_actual});
        }
    }

    // file sizes
    self.patch_file_reader.seekTo(4) catch fatal("could not seek patch file", .{});
    const original_rom_file_size = self.original_rom_file_reader.getSize() catch fatal("could not get original ROM file size", .{});
    const expected_size_original_rom = takeVariableWidthInteger(self.patchReader());
    if (expected_size_original_rom != original_rom_file_size) {
        fatal("original ROM file size does not match expected size.\n  expected size: {d}\n  actual size: {d}\n", .{ expected_size_original_rom, original_rom_file_size });
    } else {
        disp.clearAndPrint("\x1b[32moriginal ROM file size matches expected size (\x1b[0;1m{d}\x1b[0;32m)\x1b[0m\n", .{expected_size_original_rom});
    }
}

fn apply(self: *Patcher) void {
    self.original_rom_file_reader.seekTo(0) catch fatal("could not reset seek position of original ROM file", .{});
    const expected_size_patched_rom = takeVariableWidthInteger(self.patchReader()); // size of patched ROM file

    // length of metadata to skip
    const metadata_len = takeVariableWidthInteger(self.patchReader());
    if (metadata_len > 0) {
        self.patch_file_reader.seekBy(metadata_len) catch fatal("could not skip over metadata in patch file", .{});
    }

    // main data portion
    const patch_file_size = self.patch_file_reader.getSize() catch fatal("could not get patch file size", .{});
    const original_rom_file_len = self.original_rom_file_reader.getSize() catch fatal("could not get original ROM file size", .{});
    while (self.patch_file_reader.logicalPos() < patch_file_size - 12) {
        const bytes_to_skip = takeVariableWidthInteger(self.patchReader());
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

        if (self.patch_file_reader.logicalPos() < patch_file_size - 12) {
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

    // validate patched ROM checksum
    var patched_rom_file_reader = self.patched_rom_file_writer.moveToReader();
    patched_rom_file_reader.seekTo(0) catch fatal("could not seek to start of patched ROM file for checksum validation", .{});
    self.patch_file_reader.seekTo(patch_file_size - 8) catch fatal("could not to patched ROM checksum in patch file", .{});
    const checksum_expected = self.patchReader().takeInt(u32, .little) catch fatal("could not get patched ROM checksum in patch file", .{});
    const checksum_actual = calcCrc32FromFileReader(&patched_rom_file_reader, null);
    if (checksum_expected != checksum_actual) {
        fatal("patched ROM checksum does not match calculated checksum\n  expected: 0x{x:0>8}\n  actual: 0x{x:0>8}\n", .{ checksum_expected, checksum_actual });
    } else {
        disp.clearAndPrint("\x1b[32mpatched ROM checksum matches calculated checksum (\x1b[0;1m0x{x:0>8}\x1b[0;32m)\x1b[0m\n", .{checksum_actual});
    }
}

fn takeVariableWidthInteger(reader: *std.Io.Reader) usize {
    var result: usize = 0;
    var shift: u6 = 0;
    while (true) {
        const byte = reader.takeByte() catch fatal("could not read byte from patch file", .{});
        if ((byte & 0x80) != 0) {
            result += @as(usize, byte & 0x7f) << shift;
            break;
        }
        result += @as(usize, byte | 0x80) << shift;
        shift += 7;
    }
    return result;
}

/// Calculates a 32-bit CRC checksum from a file reader.
/// Pass `null` to `amount_to_read` to read the entire file.
fn calcCrc32FromFileReader(file_reader: *std.fs.File.Reader, amount_to_read: ?usize) u32 {
    file_reader.seekTo(0) catch fatal("could not reset seek position of file reader", .{});
    const file_size = file_reader.getSize() catch fatal("could not get file size from file reader", .{});
    var reader = &file_reader.interface;

    var crc32: u32 = 0xffffffff;
    for (0..amount_to_read orelse file_size) |_| {
        const byte = reader.takeByte() catch |e| fatal("{} could not read byte from reader", .{e});
        crc32 ^= byte;
        crc32 = (crc32 >> 8) ^ crc32_table[crc32 & 0xff];
    }

    return ~crc32;
}

test calcCrc32FromFileReader {
    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const f = try tmp_dir.dir.createFile("crc32-check", .{ .read = true });
    defer f.close();
    var f_file_writer = f.writer(&.{});

    {
        var f_reader_buf: [1024]u8 = undefined;
        var f_file_reader = f.reader(&f_reader_buf);
        try f_file_writer.interface.writeAll("abcde");
        try std.testing.expectEqual(0x8587D865, calcCrc32FromFileReader(&f_file_reader, null));
    }
    try f_file_writer.seekTo(0);
    {
        var f_reader_buf: [1024]u8 = undefined;
        var f_file_reader = f.reader(&f_reader_buf);
        try f_file_writer.interface.writeAll(&[_]u8{ 0xf3, 0x85, 0x9a, 0x84, 0xfc, 0x24, 0xde, 0x22 });
        try std.testing.expectEqual(0x0f5cc4b4, calcCrc32FromFileReader(&f_file_reader, null));
    }
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
