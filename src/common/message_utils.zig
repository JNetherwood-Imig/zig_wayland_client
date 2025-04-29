pub const GenericNewId = struct {
    interface: String,
    version: u32,
    id: u32,
};

pub inline fn roundup4(value: anytype) @TypeOf(value) {
    switch (@typeInfo(@TypeOf(value))) {
        .int => {},
        else => @compileError("Expected an integer"),
    }

    return (value + 3) & ~@as(@TypeOf(value), 3);
}

test "roundup4" {
    const i32_3: i32 = 3;
    const usize_9: usize = 9;
    const i8_12: i8 = 12;

    roundup4(@as(f64, 4.0));
    try std.testing.expectEqual(@as(i32, 4), roundup4(i32_3));
    try std.testing.expectEqual(@as(usize, 12), roundup4(usize_9));
    try std.testing.expectEqual(@as(i8, 12), roundup4(i8_12));
}

pub const Header = packed struct {
    object: u32,
    opcode: u16,
    length: u16,
};

pub const String = [:0]const u8;

pub const Array = []const u8;

const std = @import("std");
