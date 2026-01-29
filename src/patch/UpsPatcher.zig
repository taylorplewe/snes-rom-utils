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
}

fn apply(self: *Patcher) void {
    self.patch_file_reader.seekTo(4) catch fatal("could not seek patch file", .{});
    _ = takeVariableWidthInteger(self);
    _ = takeVariableWidthInteger(self);

    const patch_file_len = self.patch_file_reader.getSize() catch fatal("could not get patch file size", .{});
    const original_rom_file_len = self.original_rom_file_reader.getSize() catch fatal("could not get original ROM file size", .{});
    var printed = false;
    while (self.patch_file_reader.logicalPos() < patch_file_len - 12) {
        const bytes_to_skip = takeVariableWidthInteger(self);
        if (!printed) {
            std.debug.print("bytes to skip: {}\n", .{bytes_to_skip});
        }
        if (bytes_to_skip > 0) {
            if (self.original_rom_file_reader.logicalPos() >= original_rom_file_len) {
                // _ = self.patchedRomWriter().splatByte(0, bytes_to_skip) catch fatal("could not write 0s to patched ROM file", .{});
                for (0..bytes_to_skip) |_| {
                    _ = self.patchedRomWriter().writeByte(0) catch fatal("could not write 0s to patched ROM file", .{});
                }
            } else {
                if (!printed) {
                    std.debug.print(" original rom pos: {}\n", .{self.original_rom_file_reader.logicalPos()});
                }
                self.original_rom_file_reader.seekBy(@intCast(bytes_to_skip)) catch fatal("could not seek original ROM file", .{});
                self.patched_rom_file_writer.seekTo(self.original_rom_file_reader.logicalPos()) catch fatal("could not seek patched ROM file", .{});
                if (!printed) {
                    std.debug.print(" original rom pos AFTER skip: {}\n", .{self.original_rom_file_reader.logicalPos()});
                }
            }
        }

        var patch_byte_to_xor = self.patchReader().takeByte() catch fatal("could not read XOR byte from patch file", .{});
        while (patch_byte_to_xor != 0) {
            if (!printed) {
                std.debug.print("byte: 0x{X}\n", .{patch_byte_to_xor});
            }
            if (self.original_rom_file_reader.logicalPos() >= original_rom_file_len) {
                // std.debug.print("HIT MAX\n", .{});
                // std.debug.print(" BEFORE PATCHED ROM WRITE current original rom pos: {} pos pos: {}\n", .{ self.original_rom_file_reader.logicalPos(), self.original_rom_file_reader.pos });
                self.patchedRomWriter().writeByte(patch_byte_to_xor) catch fatal("could not write byte to patched ROM file", .{});
                // std.debug.print(" AFTER PATCHED ROM WRITE current original rom pos: {} pos pos: {}\n", .{ self.original_rom_file_reader.logicalPos(), self.original_rom_file_reader.pos });
            } else {
                if (self.original_rom_file_reader.logicalPos() > 3_000_000) {
                    // std.debug.print(" current original rom pos: {} pos pos: {}\n", .{ self.original_rom_file_reader.logicalPos(), self.original_rom_file_reader.pos });
                }
                const original_byte = self.originalRomReader().takeByte() catch fatal("could not read byte from original ROM file", .{});
                self.patchedRomWriter().writeByte(original_byte ^ patch_byte_to_xor) catch fatal("could not write XOR'd byte to patched ROM file", .{});
            }

            patch_byte_to_xor = self.patchReader().takeByte() catch fatal("could not read XOR byte from patch file", .{});
        }

        if (self.original_rom_file_reader.logicalPos() >= original_rom_file_len) {
            self.patchedRomWriter().writeByte(0) catch fatal("could not write 0 to patched ROM file", .{});
        } else {
            self.originalRomReader().discardAll(1) catch fatal("could not discard byte from original ROM file", .{});
            self.patched_rom_file_writer.seekTo(self.original_rom_file_reader.logicalPos()) catch fatal("could not seek patched ROM file", .{});
        }

        if (!printed) {
            std.debug.print("\n\n\n", .{});
        }
        printed = true;
    }
    self.patchedRomWriter().flush() catch fatal("could not flush patched ROM writer", .{});
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
