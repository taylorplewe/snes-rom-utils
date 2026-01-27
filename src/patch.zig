const std = @import("std");
const disp = @import("disp.zig");

pub fn patch(args: [][:0]u8) void {
    if (args.len < 2) {
        disp.printErrorAndExit("must provide ROM filepath followed by IPS patch filepath");
    }
    // const rom_path = args[0];
    const patch_path = args[1];

    disp.print("{s}\n", .{args[1]});

    // const rom_file = std.fs.cwd().openFile(rom_path, .{ .mode = .read_write }) catch {
    //     disp.printErrorAndExit("could not open ROM file");
    //     return;
    // };
    const patch_file = std.fs.cwd().openFile(patch_path, .{ .mode = .read_write }) catch {
        disp.printErrorAndExit("could not open patch file");
        return;
    };

    var patch_buf: [1024]u8 = undefined;
    var patch_reader_core = patch_file.reader(&patch_buf);
    var patch_reader = &patch_reader_core.interface;

    if (!std.mem.eql(u8, patch_reader.peekArray(5) catch "", "PATCH")) {
        disp.printErrorAndExit("IPS patch files must begin with the word \"PATCH\"");
    }

    // perform patch
}
