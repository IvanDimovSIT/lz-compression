const std = @import("std");

pub fn RingBuffer(size: usize) type {
    return struct {
        const Self = @This();
        array: [size]u8 = undefined,
        start: usize = 0,
        length: usize = 0,

        pub fn add(self: *Self, values: []const u8) void {
            const write_start = (self.start + self.length) % size;

            for (values, 0..) |value, index| {
                const array_index = (write_start + index) % size;
                self.array[array_index] = value;
            }

            const length_change = @min(size - self.length, values.len);
            self.length += length_change;
            self.start = (self.start + values.len - length_change) % size;
        }

        pub fn addByte(self: *Self, byte: u8) void {
            const write_start = (self.start + self.length) % size;
            self.array[write_start] = byte;
            const length_change = @min(size - self.length, 1);
            self.length += length_change;
            self.start = (self.start + 1 - length_change) % size;
        }

        pub fn get(self: *const Self, index: usize) u8 {
            std.debug.assert(index < self.length);
            const arr_index = (self.start + index) % size;
            return self.array[arr_index];
        }

        pub fn getFirst(self: *const Self) u8 {
            return self.get(0);
        }

        /// returns true if the length == capacity
        pub fn isAtCapacity(self: *const Self) bool {
            return self.length == size;
        }
    };
}

pub fn FixedSizeList(T: type, size: usize) type {
    return struct {
        const Self = @This();
        array: [size]T = undefined,
        len: usize = 0,

        pub fn add(self: *Self, value: T) void {
            self.array[self.len] = value;
            self.len += 1;
        }

        pub fn clear(self: *Self) void {
            self.len = 0;
        }

        pub fn slice(self: *const Self) []const T {
            return self.array[0..self.len];
        }

        pub fn popMultipleFromFront(self: *Self, count: usize) void {
            std.debug.assert(count <= self.len);
            const new_len = self.len - count;
            var swap_buffer: [size]u8 = undefined;
            @memcpy(swap_buffer[0..new_len], self.array[count..self.len]);
            @memcpy(self.array[0..new_len], swap_buffer[0..new_len]);
            self.len = new_len;
        }
    };
}
