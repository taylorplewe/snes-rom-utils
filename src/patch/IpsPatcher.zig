const std = @import("std");
const Patcher = @import("../Patcher.zig");
const ParseError = Patcher.ParseError;

const IpsPatcher = @This();

pub fn init(patch_file: std.fs.File) ParseError!Patcher {
    var patch_reader_buf: [1024]u8 = undefined;
    var patch_reader_core = patch_file.reader(&patch_reader_buf);
    var patch_reader = &patch_reader_core.interface;
    if (!std.mem.eql(u8, patch_reader.peekArray(5) catch "", "PATCH")) {
        disp.printErrorAndExit("IPS patch files must begin with the word \"PATCH\"");
    }
    patch_reader_core.seekTo(patch_file_len - 3) catch unreachable;
    if (!std.mem.eql(u8, patch_reader.peekArray(3) catch "", "EOF")) {
        disp.printErrorAndExit("IPS patch files must end with the word \"EOF\"");
    }

    return .{
        .rom_file = rom_file,
        .vtable = &.{
            .apply = IpsPatcher.apply,
        },
    };
}

fn apply(self: *Patcher, rom_file_path: []const u8) void {
    // Implementation of apply function
}
