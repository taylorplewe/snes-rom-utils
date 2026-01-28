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

pub fn init(allocator: *const std.mem.Allocator, patch_file: std.fs.File) Patcher {
    const patch_reader_buf = allocator.alloc(u8, std.math.maxInt(u16)) catch fatal("could not allocate memory for patch file reader buffer", .{});
    const patch_reader_core = patch_file.reader(patch_reader_buf);

    return .{
        .vtable = &.{
            .validate = IpsPatcher.validate,
            .apply = IpsPatcher.apply,
        },
        .file = patch_file,
        .allocator = allocator,
        .reader_buf = patch_reader_buf,
        .reader_core = patch_reader_core,
    };
}

fn validate(self: *Patcher) void {
    const patch_file_len = self.reader_core.getSize() catch fatal("could not get patch file size", .{});
    if (!std.mem.eql(u8, self.reader().peekArray(5) catch "", "PATCH")) {
        fatal("IPS patch files must begin with the word \"PATCH\"", .{});
    }
    self.reader_core.seekTo(patch_file_len - 3) catch unreachable;
    if (!std.mem.eql(u8, self.reader().peekArray(3) catch "", "EOF")) {
        fatal("IPS patch files must end with the word \"EOF\"", .{});
    }
}

fn apply(self: *Patcher, rom_file_path: []const u8) void {
    // copy ROM file to new .patched file
    const last_index_of_period = if (std.mem.lastIndexOfScalar(u8, rom_file_path, '.')) |idx| idx else rom_file_path.len;
    const rom_file_name_base = rom_file_path[0..last_index_of_period];
    const rom_file_ext = rom_file_path[last_index_of_period..];
    const dest_dir = std.fs.cwd();
    const dest_path = std.fmt.allocPrint(self.allocator.*, "{s}.patched{s}", .{ rom_file_name_base, rom_file_ext }) catch fatal("could not allocate memory for destination path", .{});
    defer self.allocator.free(dest_path);
    dest_dir.copyFile(rom_file_path, dest_dir, dest_path, .{}) catch fatal("could not copy ROM file", .{});
    const patched_rom_file = std.fs.cwd().openFile(dest_path, .{ .mode = .write_only }) catch fatal("could not open patched ROM file for writing", .{});
    const patched_rom_writer_buf = self.allocator.alloc(u8, std.math.maxInt(u16)) catch fatal("could not allocate memory for patched ROM writer buffer", .{});
    var patched_rom_writer_core = patched_rom_file.writer(patched_rom_writer_buf);
    const patched_rom_writer = &patched_rom_writer_core.interface;

    self.reader_core.seekTo(5) catch unreachable;
    const patch_file_len = self.reader_core.getSize() catch fatal("could not get patch file size", .{});
    while (self.reader_core.logicalPos() < patch_file_len - 3) {
        const record = self.reader().takeStruct(IpsPatchRecord, .big) catch fatal("could not get IpsPatchRecord", .{});

        patched_rom_writer_core.seekTo(record.offset) catch fatal("could not seek patched ROM file to offset \x1b[1m0x{x}\x1b[0m", .{record.offset});
        if (record.length > 0) {
            self.reader().streamExact(patched_rom_writer, record.length) catch fatal("could not stream data from patch file to patched ROM file", .{});
        } else {
            const rle_length = self.reader().takeInt(u16, .big) catch fatal("could not read RLE length", .{});
            const rle_byte = self.reader().takeByte() catch fatal("could not read RLE byte", .{});
            for (0..rle_length) |_| {
                patched_rom_writer.writeByte(rle_byte) catch fatal("could not write RLE byte", .{});
            }
        }
        patched_rom_writer.flush() catch unreachable;
    }
}
