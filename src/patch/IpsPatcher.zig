const std = @import("std");
const disp = @import("../disp.zig");
const fatal = disp.fatal;
const Patcher = @import("./Patcher.zig");

const IpsPatcher = @This();
/// Offset and length are flipped because since it's packed big-endian, the whole thing is reversed
const IpsPatchRecord = packed struct {
    length: u16,
    offset: u24,
};

pub fn init(
    allocator: *const std.mem.Allocator,
    patch_file_reader: *std.fs.File.Reader,
    original_rom_file_reader: *std.fs.File.Reader,
    patched_rom_file_writer: *std.fs.File.Writer,
) Patcher {
    return .{
        .vtable = &.{
            .validate = IpsPatcher.validate,
            .apply = IpsPatcher.apply,
        },
        .allocator = allocator,
        .patch_file_reader = patch_file_reader,
        .original_rom_file_reader = original_rom_file_reader,
        .patched_rom_file_writer = patched_rom_file_writer,
    };
}

fn validate(self: *Patcher) void {
    const patch_file_len = self.patch_file_reader.getSize() catch fatal("could not get patch file size", .{});
    if (!std.mem.eql(u8, self.patchReader().peekArray(5) catch "", "PATCH")) {
        fatal("IPS patch files must begin with the word \"PATCH\"", .{});
    }
    self.patch_file_reader.seekTo(patch_file_len - 3) catch unreachable;
    if (!std.mem.eql(u8, self.patchReader().peekArray(3) catch "", "EOF")) {
        fatal("IPS patch files must end with the word \"EOF\"", .{});
    }
}

fn apply(self: *Patcher) void {
    self.patch_file_reader.seekTo(5) catch unreachable;
    const patch_file_len = self.patch_file_reader.getSize() catch fatal("could not get patch file size", .{});
    while (self.patch_file_reader.logicalPos() < patch_file_len - 3) {
        const record = self.patchReader().takeStruct(IpsPatchRecord, .big) catch fatal("could not get IpsPatchRecord", .{});

        self.patched_rom_file_writer.seekTo(record.offset) catch fatal("could not seek patched ROM file to offset \x1b[1m0x{x}\x1b[0m", .{record.offset});
        if (record.length > 0) {
            self.patchReader().streamExact(self.patchedRomWriter(), record.length) catch fatal("could not stream data from patch file to patched ROM file", .{});
        } else {
            const rle_length = self.patchReader().takeInt(u16, .big) catch fatal("could not read RLE length", .{});
            const rle_byte = self.patchReader().takeByte() catch fatal("could not read RLE byte", .{});
            for (0..rle_length) |_| {
                self.patchedRomWriter().writeByte(rle_byte) catch fatal("could not write RLE byte", .{});
            }
        }
        self.patchedRomWriter().flush() catch unreachable;
    }
}
