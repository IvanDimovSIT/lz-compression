const std = @import("std");

const lz_compression = @import("lz_compression.zig");

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const cwd = std.Io.Dir.cwd();

    var in_file = try cwd.openFile(io, "file.txt", .{ .mode = .read_only });
    defer in_file.close(io);

    var out_file = try cwd.createFile(io, "output.txt", .{});
    defer out_file.close(io);

    var read_buf: [4096]u8 = undefined;
    var write_buf: [4096]u8 = undefined;

    var file_reader = in_file.reader(io, &read_buf);
    var file_writer = out_file.writer(io, &write_buf);

    const reader = &file_reader.interface;
    const writer = &file_writer.interface;

    try lz_compression.compress(reader, writer);
    std.debug.print("Compressed!\n", .{});
}
