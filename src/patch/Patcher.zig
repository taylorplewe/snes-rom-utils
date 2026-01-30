const std = @import("std");
const disp = @import("../disp.zig");
const fatal = disp.fatal;
const Patcher = @This();

vtable: *const VTable,
allocator: *const std.mem.Allocator,

patch_file_reader: *std.fs.File.Reader,
original_rom_file_reader: *std.fs.File.Reader,
patched_rom_file_writer: *std.fs.File.Writer,

pub const VTable = struct {
    /// Validate that the file meets the format criteria
    validate: *const fn (self: *Patcher) void,

    /// Apply the patch to the ROM provided at initialization
    apply: *const fn (self: *Patcher) void,
};

pub fn validate(self: *Patcher) void {
    self.vtable.validate(self);
}

pub fn apply(self: *Patcher) void {
    self.vtable.apply(self);
}

pub inline fn patchReader(self: *Patcher) *std.io.Reader {
    return &self.patch_file_reader.*.interface;
}
pub inline fn originalRomReader(self: *Patcher) *std.io.Reader {
    return &self.original_rom_file_reader.*.interface;
}
pub inline fn patchedRomWriter(self: *Patcher) *std.io.Writer {
    return &self.patched_rom_file_writer.*.interface;
}
