const std = @import("std");
const ring_buffer_size = 1024 * 4;
const window_size = 16;
const data_structures = @import("data_structures.zig");
const RingBuffer = data_structures.RingBuffer(ring_buffer_size);
const TokenList = data_structures.FixedSizeList(Token, 8);
const Window = data_structures.FixedSizeList(u8, window_size);

const ByteMatch = packed struct { offset: u12, len: u4 };

/// len and offset are stored as the len or offset - 1
const Token = union(enum) { literal: u8, match: ByteMatch };

pub fn compress(input: *std.Io.Reader, writer: *std.Io.Writer) !void {
    defer writer.flush() catch {};
    var ring_buffer = RingBuffer{};
    var window = Window{};
    var tokens = TokenList{};

    try fillWindow(&window, input);
    while (window.len > 0) {
        const bytes_matched = matchWindow(&window, &ring_buffer, &tokens);
        window.popMultipleFromFront(bytes_matched);
        try fillWindow(&window, input);
        const token_slice = tokens.slice();
        if (token_slice.len == 8) {
            try writeToken(writer, token_slice);
            tokens.clear();
        }
    }
    try writeToken(writer, tokens.slice());
}

/// returns the size of the matched section
fn matchWindow(window: *Window, ring_buffer: *RingBuffer, tokens: *TokenList) usize {
    var scan_window = window.slice();
    std.debug.assert(scan_window.len >= 1);
    if (scan_window.len <= 2) {
        matchSingleByte(window, ring_buffer, tokens);
        return 1;
    }

    while (scan_window.len > 2) : (scan_window = scan_window[0..(scan_window.len - 1)]) {
        if (matchScanWindow(ring_buffer, scan_window)) |token| {
            tokens.add(token);
            ring_buffer.add(scan_window);
            return scan_window.len;
        }
    }

    matchSingleByte(window, ring_buffer, tokens);
    return 1;
}

fn matchScanWindow(ring_buffer: *const RingBuffer, scan_window: []const u8) ?Token {
    if (ring_buffer.length < scan_window.len) {
        return null;
    }

    var index: isize = @intCast(ring_buffer.length - scan_window.len);
    while (index >= 0) : (index -= 1) {
        const ring_index: usize = @intCast(index);
        if (checkScanWindowMatches(ring_buffer, scan_window, ring_index)) {
            const ring_len: isize = @intCast(ring_buffer.length);
            const scan_len: isize = @intCast(scan_window.len);
            const index_isize: isize = @intCast(index);
            const match_offset: u12 = @intCast(ring_len - index_isize - 1);
            const match_len: u4 = @intCast(scan_len - 1);
            return .{ .match = .{ .offset = match_offset, .len = match_len } };
        }
    }

    return null;
}

fn checkScanWindowMatches(ring_buffer: *const RingBuffer, scan_window: []const u8, ring_index: usize) bool {
    for (scan_window, 0..) |scan_byte, window_index| {
        if (ring_buffer.get(ring_index + window_index) != scan_byte) {
            return false;
        }
    }

    return true;
}

fn matchSingleByte(window: *Window, ring_buffer: *RingBuffer, tokens: *TokenList) void {
    const byte = window.slice()[0];
    ring_buffer.addByte(byte);
    tokens.add(.{ .literal = byte });
}

fn fillWindow(window: *Window, input: *std.Io.Reader) !void {
    const bytes_read = try input.readSliceShort(window.array[window.len..]);
    window.len += bytes_read;
}

fn move_back_window_buffer(window_buffer: *[window_size]u8, amoount: usize) void {
    std.debug.assert(amoount <= window_size);
    var swap_buffer: [window_size]u8 = undefined;
    @memcpy(swap_buffer[0 .. window_size - amoount], window_buffer[amoount..]);
    @memcpy(window_buffer[0 .. window_size - amoount], swap_buffer[0 .. window_size - amoount]);
}

fn writeToken(writer: *std.Io.Writer, tokens: []const Token) !void {
    const header_mask: u8 = 0b1000_0000;
    var header: u8 = 0;
    for (tokens, 0..) |token, index| {
        const shift_amount: u3 = @intCast(index);
        // literal = 0
        // match = 1
        switch (token) {
            .match => header = header | (header_mask >> shift_amount),
            else => {},
        }
    }

    try writer.writeByte(header);
    for (tokens) |token| {
        switch (token) {
            .match => |match| try writer.writeAll(std.mem.asBytes(&match)),
            .literal => |literal| try writer.writeByte(literal),
        }
    }
}

pub fn decompress(input: *std.Io.Reader, writer: *std.Io.Writer) !void {
    defer writer.flush() catch {};
    var ring_buffer = RingBuffer{};
    var tokens = TokenList{};

    try fillTokens(&tokens, input);
    while (tokens.len > 0) : (try fillTokens(&tokens, input)) {
        try decompressTokens(writer, &ring_buffer, &tokens);
        tokens.clear();
    }
    try flushRingBuffer(writer, &ring_buffer);
}

fn fillTokens(tokens: *TokenList, input: *std.Io.Reader) !void {
    const header = input.takeByte() catch |e| switch (e) {
        error.EndOfStream => return,
        else => return e,
    };
    var i: usize = 0;

    while (i < 8 and hasNextByte(input)) : (i += 1) {
        const tag = (header >> @intCast(7 - i)) & 1;
        const token = switch (tag) {
            0 => Token{ .literal = try input.takeByte() },
            1 => Token{ .match = @bitCast((try input.takeArray(2)).*) },
            else => unreachable,
        };
        tokens.add(token);
    }
}

fn hasNextByte(input: *std.Io.Reader) bool {
    _ = input.peekByte() catch return false;
    return true;
}

fn decompressTokens(writer: *std.Io.Writer, ring_buffer: *RingBuffer, tokens: *TokenList) !void {
    const token_slice = tokens.slice();
    for (token_slice) |token| {
        switch (token) {
            .literal => |byte| {
                try writeByteAndFlush(byte, writer, ring_buffer);
            },
            .match => |match| {
                const offset: usize = match.offset + 1;
                const start = ring_buffer.length - offset;
                const end = start + match.len;
                var i = start;
                while (i <= end) : (i += 1) {
                    const byte = ring_buffer.get(i);
                    try writeByteAndFlush(byte, writer, ring_buffer);
                }
            },
        }
    }
}

fn writeByteAndFlush(byte: u8, writer: *std.Io.Writer, ring_buffer: *RingBuffer) !void {
    if (ring_buffer.isAtCapacity()) {
        try writer.writeByte(ring_buffer.getFirst());
    }
    ring_buffer.addByte(byte);
}

fn flushRingBuffer(writer: *std.Io.Writer, ring_buffer: *RingBuffer) !void {
    var i: usize = 0;
    while (i < ring_buffer.length) : (i += 1) {
        try writer.writeByte(ring_buffer.get(i));
    }
}
