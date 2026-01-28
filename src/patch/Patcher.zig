const std = @import("std");
const Patcher = @This();

file: std.fs.File,
vtable: *const VTable,

pub const VTable = struct {
    /// Apply the patch to the ROM at the given path.
    apply: *const fn (self: *Patcher, rom_file_path: []const u8) void,
};

pub const ParseError = error{
    InvalidFormat,
};
