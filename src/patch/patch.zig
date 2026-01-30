const std = @import("std");
const disp = @import("../disp.zig");
const fatal = disp.fatal;
const Patcher = @import("./Patcher.zig");
const IpsPatcher = @import("./IpsPatcher.zig");
const UpsPatcher = @import("./UpsPatcher.zig");

const PatchFormat = enum {
    ips,
    ups,
};

pub fn patch(allocator: *const std.mem.Allocator, args: [][:0]u8) void {
    if (args.len < 2) {
        fatal("must provide ROM filepath followed by IPS patch filepath", .{});
    }
    const original_rom_path = args[0];
    const patch_path = args[1];

    // patch file I/O
    const patch_path_ext = patch_path[((std.mem.lastIndexOfScalar(u8, patch_path, '.') orelse patch_path.len) + 1)..];
    const patch_file_format = std.meta.stringToEnum(PatchFormat, patch_path_ext) orelse fatal("unsupported patch file extension \x1b[1m{s}\x1b[0m", .{patch_path_ext});
    const patch_file = std.fs.cwd().openFile(patch_path, .{ .mode = .read_only }) catch fatal("could not open patch file \x1b[1m{s}\x1b[0m", .{patch_path});
    const patch_reader_buf = allocator.alloc(u8, std.math.maxInt(u16)) catch fatal("could not allocate memory for patch reader buffer", .{});
    var patch_file_reader = patch_file.reader(patch_reader_buf);

    // original ROM I/O
    const original_rom_path_last_index_of_period = std.mem.lastIndexOfScalar(u8, original_rom_path, '.') orelse original_rom_path.len;
    const original_rom_path_base = original_rom_path[0..original_rom_path_last_index_of_period];
    const original_rom_path_ext = original_rom_path[(original_rom_path_last_index_of_period + 1)..];
    const original_rom_file = std.fs.cwd().openFile(original_rom_path, .{ .mode = .read_only }) catch fatal("could not open original ROM file \x1b[1m{s}\x1b[0m", .{original_rom_path});
    const original_rom_reader_buf = allocator.alloc(u8, std.math.maxInt(u16)) catch fatal("could not allocate memory for original ROM reader buffer", .{});
    var original_rom_file_reader = original_rom_file.reader(original_rom_reader_buf);

    // patched ROM I/O
    const patched_rom_path = std.fmt.allocPrint(allocator.*, "{s}.patched.{s}", .{ original_rom_path_base, original_rom_path_ext }) catch fatal("could not allocate memory for patched ROM path", .{});
    std.fs.cwd().copyFile(original_rom_path, std.fs.cwd(), patched_rom_path, .{}) catch fatal("could not copy ROM file", .{});
    const patched_rom_file = std.fs.cwd().openFile(patched_rom_path, .{ .mode = .write_only }) catch fatal("could not open patched ROM file \x1b[1m{s}\x1b[0m", .{patched_rom_path});
    const patched_rom_writer_buf = allocator.alloc(u8, std.math.maxInt(u16)) catch fatal("could not allocate memory for patched ROM writer buffer", .{});
    var patched_rom_file_writer = patched_rom_file.writer(patched_rom_writer_buf);

    defer {
        patch_file.close();
        original_rom_file.close();
        patched_rom_file.close();
        allocator.free(patch_reader_buf);
        allocator.free(original_rom_reader_buf);
        allocator.free(patched_rom_writer_buf);
    }

    var patcher: Patcher = switch (patch_file_format) {
        .ips => IpsPatcher.init(
            allocator,
            &patch_file_reader,
            &original_rom_file_reader,
            &patched_rom_file_writer,
        ),
        .ups => UpsPatcher.init(
            allocator,
            &patch_file_reader,
            &original_rom_file_reader,
            &patched_rom_file_writer,
        ),
    };

    disp.printLoading("patching ROM");
    patcher.validate();
    patcher.apply();
    // patcher.patchedRomWriter().flush() catch fatal("could not flush patched ROM writer", .{});
    disp.clearAndPrint("\x1b[32mROM file \x1b[0;1m{s}\x1b[0;32m patched successfully", .{original_rom_path});
}
