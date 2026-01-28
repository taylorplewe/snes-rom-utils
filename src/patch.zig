const std = @import("std");
const disp = @import("disp.zig");

const IpsPatchRecord = packed struct {
    length: u16,
    offset: u24,
};

pub fn patch(allocator: std.mem.Allocator, args: [][:0]u8) void {
    if (args.len < 2) {
        disp.printErrorAndExit("must provide ROM filepath followed by IPS patch filepath");
    }
    const rom_path = args[0];
    const patch_path = args[1];

    // copy ROM file to new .patched file
    const last_index_of_period = if (std.mem.lastIndexOfScalar(u8, rom_path, '.')) |idx| idx else rom_path.len;
    const rom_file_name_base = rom_path[0..last_index_of_period];
    const rom_file_ext = rom_path[last_index_of_period..];
    const dest_dir = std.fs.cwd();
    const dest_path = std.fmt.allocPrint(allocator, "{s}.patched{s}", .{ rom_file_name_base, rom_file_ext }) catch {
        disp.printErrorAndExit("could not allocate memory for destination path");
        return;
    };
    defer allocator.free(dest_path);
    dest_dir.copyFile(rom_path, dest_dir, dest_path, .{}) catch {
        disp.printErrorAndExit("could not copy ROM file");
        return;
    };
    const patched_rom_file = std.fs.cwd().openFile(dest_path, .{ .mode = .write_only }) catch {
        disp.printErrorAndExit("could not open patched ROM file for writing");
        return;
    };
    const patched_rom_writer_buf = allocator.alloc(u8, std.math.maxInt(u16)) catch {
        disp.printErrorAndExit("could not allocate memory for patched ROM writer buffer");
        return;
    };
    var patched_rom_writer_core = patched_rom_file.writer(patched_rom_writer_buf);
    const patched_rom_writer = &patched_rom_writer_core.interface;

    // open patch file
    const patch_file = std.fs.cwd().openFile(patch_path, .{ .mode = .read_write }) catch {
        disp.printErrorAndExit("could not open patch file");
        return;
    };
    const patch_reader_buf = allocator.alloc(u8, std.math.maxInt(u16)) catch {
        disp.printErrorAndExit("could not allocate memory for patch file reader buffer");
        return;
    };
    defer allocator.free(patch_reader_buf);
    var patch_reader_core = patch_file.reader(patch_reader_buf);
    var patch_reader = &patch_reader_core.interface;
    const patch_file_len = patch_reader_core.getSize() catch {
        disp.printErrorAndExit("could not get patch file size");
        return;
    };

    // verify it's a valid IPS patch file
    if (!std.mem.eql(u8, patch_reader.peekArray(5) catch "", "PATCH")) {
        disp.printErrorAndExit("IPS patch files must begin with the word \"PATCH\"");
    }
    patch_reader_core.seekTo(patch_file_len - 3) catch unreachable;
    if (!std.mem.eql(u8, patch_reader.peekArray(3) catch "", "EOF")) {
        disp.printErrorAndExit("IPS patch files must end with the word \"EOF\"");
    }
    patch_reader_core.seekTo(5) catch unreachable;

    // perform patch
    while (patch_reader_core.logicalPos() < patch_file_len - 3) {
        const record = patch_reader.takeStruct(IpsPatchRecord, .big) catch {
            disp.printErrorAndExit("could not get IpsPatchRecord");
            return;
        };

        patched_rom_writer_core.seekTo(record.offset) catch {
            disp.printErrorAndExit("could not seek patched ROM file to offset");
        };
        if (record.length > 0) {
            patch_reader.streamExact(patched_rom_writer, record.length) catch {
                disp.printErrorAndExit("could not stream data from patch file to patched ROM file");
            };
        } else {
            const rle_length = patch_reader.takeInt(u16, .big) catch {
                disp.printErrorAndExit("could not read RLE length");
                return;
            };
            const rle_byte = patch_reader.takeByte() catch {
                disp.printErrorAndExit("could not read RLE byte");
                return;
            };
            for (0..rle_length) |_| {
                patched_rom_writer.writeByte(rle_byte) catch {
                    disp.printErrorAndExit("could not write RLE byte");
                };
            }
        }
        patched_rom_writer.flush() catch unreachable;
    }
}
