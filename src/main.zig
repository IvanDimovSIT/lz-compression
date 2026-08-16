const std = @import("std");

const lz_compression = @import("lz_compression.zig");
const Operation = fn (*std.Io.Reader, *std.Io.Writer) anyerror!void;

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    if (args.len == 4) {
        const operation = args[1];
        const in_path = args[2];
        const out_path = args[3];
        if (std.mem.eql(u8, operation, "c")) {
            try performOperation(io, in_path, out_path, lz_compression.compress);
        } else if (std.mem.eql(u8, operation, "d")) {
            try performOperation(io, in_path, out_path, lz_compression.decompress);
        } else {
            std.log.err("Invalid operation '{s}'", .{operation});
            showHelp();
        }
    } else {
        showHelp();
    }
}

fn showHelp() void {
    std.log.info("Compress with: c <input file> <compressed file>", .{});
    std.log.info("Decompress with: d <compressed file> <output file>", .{});
}

fn performOperation(io: std.Io, in_path: []const u8, out_path: []const u8, operation: Operation) !void {
    const cwd = std.Io.Dir.cwd();
    var in_file = cwd.openFile(io, in_path, .{ .mode = .read_only }) catch |err| {
        std.log.err("Error reading file: {s} ({})", .{ in_path, err });
        return;
    };
    defer in_file.close(io);

    var out_file = cwd.createFile(io, out_path, .{}) catch |err| {
        std.log.err("Error writing file: {s} ({})", .{ out_path, err });
        return err;
    };
    defer out_file.close(io);

    var read_buf: [4096]u8 = undefined;
    var write_buf: [4096]u8 = undefined;

    var file_reader = in_file.reader(io, &read_buf);
    var file_writer = out_file.writer(io, &write_buf);

    const reader = &file_reader.interface;
    const writer = &file_writer.interface;

    try operation(reader, writer);
    std.log.info("Created: {s}", .{out_path});
}

test {
    const test_dir_path = "test-files/";
    const compressed_path = "compressed";
    const decompressed_path = "decompressed";
    const io = std.testing.io;
    const gpa = std.testing.allocator;
    const cwd = std.Io.Dir.cwd();
    const dir = try cwd.openDir(io, test_dir_path, .{ .iterate = true });
    defer dir.close(io);
    defer _ = std.Io.Dir.cwd().deleteFile(io, compressed_path) catch |err| std.debug.print("{}", .{err});
    defer _ = std.Io.Dir.cwd().deleteFile(io, decompressed_path) catch |err| std.debug.print("{}", .{err});
    var file_iterator = dir.iterate();
    while (try file_iterator.next(io)) |file| {
        switch (file.kind) {
            .file => {
                const input_path = try std.mem.concat(gpa, u8, &.{ test_dir_path, file.name });
                defer gpa.free(input_path);
                try performOperation(io, input_path, compressed_path, lz_compression.compress);
                try performOperation(io, compressed_path, decompressed_path, lz_compression.decompress);
                const original = try dir.readFileAlloc(io, file.name, gpa, .unlimited);
                defer gpa.free(original);
                const decompressed = try cwd.readFileAlloc(io, decompressed_path, gpa, .unlimited);
                defer gpa.free(decompressed);
                try std.testing.expectEqualSlices(u8, original, decompressed);
            },
            else => {},
        }
    }
}
