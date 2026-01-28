const std = @import("std");
const Patcher = @This();

vtable: *const VTable,
file: std.fs.File,
allocator: *const std.mem.Allocator,

reader_buf: []u8,
reader_core: std.fs.File.Reader,
reader: *std.io.Reader,

pub const VTable = struct {
    /// Validate that the file meets the format criteria
    validate: *const fn (self: *Patcher) void,

    /// Apply the patch to the ROM at the given path.
    apply: *const fn (self: *Patcher, rom_file_path: []const u8) void,
};

pub fn validate(self: *Patcher) void {
    self.vtable.validate(self);
}

pub fn apply(self: *Patcher, rom_file_path: []const u8) void {
    self.vtable.apply(self, rom_file_path);
}
