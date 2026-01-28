const std = @import("std");
const disp = @import("../disp.zig");
const fatal = disp.fatal;
const Patcher = @import("./Patcher.zig");
const IpsPatcher = @import("./IpsPatcher.zig");

const PatchFormat = enum {
    ips,
    ups,
};

pub fn patch(allocator: *const std.mem.Allocator, args: [][:0]u8) void {
    if (args.len < 2) {
        fatal("must provide ROM filepath followed by IPS patch filepath", .{});
    }
    const rom_path = args[0];
    const patch_path = args[1];

    const last_index_of_period = if (std.mem.lastIndexOfScalar(u8, patch_path, '.')) |idx| idx else patch_path.len;
    const patch_file_ext = patch_path[last_index_of_period + 1 ..];
    const patch_format = std.meta.stringToEnum(PatchFormat, patch_file_ext) orelse fatal("unsupported patch file extension \x1b[1m{s}\x1b[0m", .{patch_file_ext});
    const patch_file = std.fs.cwd().openFile(patch_path, .{ .mode = .read_only }) catch fatal("could not open patch file \x1b[1m{s}\x1b[0m", .{patch_path});

    var patcher: Patcher = switch (patch_format) {
        .ips => IpsPatcher.init(allocator, patch_file),
        else => fatal("unsupported patch file extension \x1b[1m{s}\x1b[0m", .{patch_file_ext}),
    };

    patcher.validate();
    patcher.apply(rom_path);
}
