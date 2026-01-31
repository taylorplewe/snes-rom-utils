// the BPS patch file format documentation I used can be found here: http://justsolve.archiveteam.org/wiki/UPS_(binary_patch_format)

const std = @import("std");
const disp = @import("../disp.zig");
const fatal = disp.fatal;
const fatalFmt = disp.fatalFmt;
const Patcher = @import("./Patcher.zig");

const BpsPatcher = @This();
const ActionKind = enum {
    SourceRead,
    TargetRead,
    SourceCopy,
    TargetCopy,
};
const Action = struct {
    kind: ActionKind,
    length: usize,
};

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
        fatal("UPS patch files must begin with the word \"UPS1\"");
    }

    // original ROM checksum
    const patch_file_size = self.patch_file_reader.getSize() catch fatal("could not get size of patch file");
    self.patch_file_reader.seekTo(patch_file_size - 12) catch fatal("could not seek to original ROM checksum in patch file");
    {
        const checksum_expected = self.patchReader().takeInt(u32, .little) catch fatal("could not get original ROM checksum in patch file");
        const checksum_actual = calcCrc32FromFileReader(self.original_rom_file_reader, null);
        if (checksum_expected != checksum_actual) {
            fatalFmt("original ROM checksum does not match calculated checksum\n  expected: 0x{x:0>8}\n  actual: 0x{x:0>8}\n", .{ checksum_expected, checksum_actual });
        } else {
            disp.clearAndPrint("\x1b[32moriginal ROM checksum matches calculated checksum (\x1b[0;1m0x{x:0>8}\x1b[0;32m)\x1b[0m\n", .{checksum_actual});
        }
    }

    // patch file checksum
    self.patch_file_reader.seekTo(patch_file_size - 4) catch fatal("could not seek to final checksum in patch file");
    {
        const checksum_expected = self.patchReader().takeInt(u32, .little) catch fatal("could not get final checksum in patch file");
        const checksum_actual = calcCrc32FromFileReader(self.patch_file_reader, patch_file_size - 4);
        if (checksum_expected != checksum_actual) {
            fatalFmt("patch file checksum does not match calculated checksum\n  expected: 0x{x:0>8}\n  actual: 0x{x:0>8}\n", .{ checksum_expected, checksum_actual });
        } else {
            disp.clearAndPrint("\x1b[32mpatch file checksum matches calculated checksum (\x1b[0;1m0x{x:0>8}\x1b[0;32m)\x1b[0m\n", .{checksum_actual});
        }
    }

    // file sizes
    self.patch_file_reader.seekTo(4) catch fatal("could not seek patch file");
    const original_rom_file_size = self.original_rom_file_reader.getSize() catch fatal("could not get original ROM file size");
    const expected_size_original_rom = takeVariableWidthInteger(self.patchReader());
    if (expected_size_original_rom != original_rom_file_size) {
        fatalFmt("original ROM file size does not match expected size.\n  expected size: {d}\n  actual size: {d}\n", .{ expected_size_original_rom, original_rom_file_size });
    } else {
        disp.clearAndPrint("\x1b[32moriginal ROM file size matches expected size (\x1b[0;1m{d}\x1b[0;32m)\x1b[0m\n", .{expected_size_original_rom});
    }
}

fn apply(self: *Patcher) void {
    errdefer self.patchedRomWriter().flush() catch unreachable;

    self.original_rom_file_reader.seekTo(0) catch fatal("could not reset seek position of original ROM file");
    const expected_size_patched_rom = takeVariableWidthInteger(self.patchReader()); // size of patched ROM file

    // skip over optional metadata
    const metadata_len = takeVariableWidthInteger(self.patchReader());
    if (metadata_len > 0) {
        self.patch_file_reader.seekBy(@intCast(metadata_len)) catch fatal("could not skip over metadata in patch file");
    }

    // main data portion
    var source_relative_offset: u64 = 0;
    var target_relative_offset: u64 = 0;
    var action_num: usize = 0;
    const patch_file_size = self.patch_file_reader.getSize() catch fatal("could not get patch file size");
    while (self.patch_file_reader.logicalPos() < patch_file_size - 12) {
        const action_kind_and_length = takeVariableWidthInteger(self.patchReader());
        const action: Action = .{
            .kind = @enumFromInt(action_kind_and_length & 0b11),
            .length = (action_kind_and_length >> 2) + 1,
        };

        switch (action.kind) {
            .SourceRead => {
                self.original_rom_file_reader.seekTo(self.patched_rom_file_writer.pos) catch fatal("could not seek original rom to patched rom's position");
                self.originalRomReader().streamExact(self.patchedRomWriter(), action.length) catch fatal("could not stream data from original ROM to patched ROM during SourceRead");
            },
            .TargetRead => {
                self.patchReader().streamExact(self.patchedRomWriter(), action.length) catch fatal("could not stream data from patch file to patched ROM during TargetRead");
            },
            .SourceCopy => {
                const offset_data = takeVariableWidthInteger(self.patchReader());
                const relative_offset = offset_data >> 1;
                const original_rom_file_size = self.original_rom_file_reader.getSize() catch fatal("could not get size of original ROM size");

                if (offset_data & 1 == 1) {
                    if (relative_offset > source_relative_offset) {
                        fatalFmt("SourceCopy negative relative offset is larger than the current source relative offset\n relative offset: {}\n source relative offset: {}", .{ relative_offset, source_relative_offset });
                    }
                    source_relative_offset -= relative_offset;
                } else {
                    if (source_relative_offset + relative_offset > original_rom_file_size) {
                        fatalFmt("SourceCopy positive relative offset is larger than the current patched ROM file size\n relative offset: {}\n original ROM file size: {}", .{ relative_offset, original_rom_file_size });
                    }
                    source_relative_offset += relative_offset;
                }

                self.original_rom_file_reader.seekTo(source_relative_offset) catch fatal("could not seek to new position in original file");
                self.originalRomReader().streamExact(self.patchedRomWriter(), action.length) catch fatal("could not stream data from original ROM to patched ROM during SourceCopy");
                source_relative_offset += action.length;
            },
            .TargetCopy => {
                self.patchedRomWriter().flush() catch fatal("could not flush patched ROM file prior to creating temporary reader");
                const offset_data = takeVariableWidthInteger(self.patchReader());
                const relative_offset = offset_data >> 1;
                const prev_patched_rom_file_pos = self.patched_rom_file_writer.pos;
                if (offset_data & 1 == 1) {
                    if (relative_offset > target_relative_offset) {
                        fatalFmt("TargetCopy negative relative offset is larger than the current target relative offset\n relative offset: {}\n target relative offset: {}", .{ relative_offset, target_relative_offset });
                    }
                    target_relative_offset -= relative_offset;
                } else {
                    if (target_relative_offset + relative_offset > prev_patched_rom_file_pos) {
                        fatalFmt("TargetCopy positive relative offset is larger than the current patched ROM file size\n relative offset: {}\n patched ROM file size: {}", .{ relative_offset, prev_patched_rom_file_pos });
                    }
                    target_relative_offset += relative_offset;
                }

                // set up new temporary reader
                var patched_rom_reader_buf: [1]u8 = undefined;
                var patched_rom_file_reader = self.patched_rom_file_writer.file.reader(&patched_rom_reader_buf); // un-buffered because we don't know how far back the read head is from the write head
                var patched_rom_reader = &patched_rom_file_reader.interface;
                patched_rom_file_reader.seekTo(target_relative_offset) catch fatal("could not seek temporary patched ROM reader");
                for (0..action.length) |_| {
                    const byte = patched_rom_reader.takeByte() catch fatal("could not read byte from patched ROM file");
                    self.patchedRomWriter().writeByte(byte) catch fatal("could not write byte to patched ROM file from itself");
                    self.patchedRomWriter().flush() catch fatal("could not flush patched ROM file after writing byte");
                }
                // patched_rom_reader.streamExact(self.patchedRomWriter(), action.length) catch |e| fatalFmt("{} could not stream data from patched ROM to itself in TargetCopy", .{e});
                target_relative_offset += action.length;
            },
        }
        self.patchedRomWriter().flush() catch unreachable;
        action_num += 1;
    }
    self.patchedRomWriter().flush() catch fatal("could not flush patched ROM file");

    // validate patched ROM size
    const patched_rom_file_len = self.patched_rom_file_writer.pos;
    if (patched_rom_file_len != expected_size_patched_rom) {
        fatalFmt("final patched ROM file size does not match expected size.\n  expected size: {d}\n  actual size: {d}\n", .{ expected_size_patched_rom, patched_rom_file_len });
    } else {
        disp.clearAndPrint("\x1b[32mfinal patched ROM file size matches expected size (\x1b[0;1m{d}\x1b[0;32m)\x1b[0m\n", .{expected_size_patched_rom});
    }

    // validate patched ROM checksum
    var patched_rom_file_reader = self.patched_rom_file_writer.moveToReader();
    patched_rom_file_reader.seekTo(0) catch fatal("could not seek to start of patched ROM file for checksum validation");
    self.patch_file_reader.seekTo(patch_file_size - 8) catch fatal("could not to patched ROM checksum in patch file");
    const checksum_expected = self.patchReader().takeInt(u32, .little) catch fatal("could not get patched ROM checksum in patch file");
    const checksum_actual = calcCrc32FromFileReader(&patched_rom_file_reader, null);
    if (checksum_expected != checksum_actual) {
        fatalFmt("patched ROM checksum does not match calculated checksum\n  expected: 0x{x:0>8}\n  actual: 0x{x:0>8}\n", .{ checksum_expected, checksum_actual });
    } else {
        disp.clearAndPrint("\x1b[32mpatched ROM checksum matches calculated checksum (\x1b[0;1m0x{x:0>8}\x1b[0;32m)\x1b[0m\n", .{checksum_actual});
    }
}

fn takeVariableWidthInteger(reader: *std.Io.Reader) usize {
    var result: usize = 0;
    var shift: u6 = 0;
    while (true) {
        const byte = reader.takeByte() catch fatal("could not read byte from patch file");
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
    file_reader.seekTo(0) catch fatal("could not reset seek position of file reader");
    const file_size = file_reader.getSize() catch fatal("could not get file size from file reader");
    var reader = &file_reader.interface;

    var crc32: u32 = 0xffffffff;
    for (0..amount_to_read orelse file_size) |_| {
        const byte = reader.takeByte() catch |e| fatalFmt("{} could not read byte from reader", .{e});
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
