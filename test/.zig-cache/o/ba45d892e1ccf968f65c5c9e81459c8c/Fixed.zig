const std = @import("std");
const Self = @This();

data: i32,

pub fn from(comptime T: type, value: T) Self {
    return switch (@typeInfo(T)) {
        .int => Self{ .data = value * 256 },
        .float => Self{ .data = value * 256.0 },
        else => @compileError("expected a float or int type for Fixed.to"),
    };
}

pub fn to(self: Self, comptime T: type) T {
    return switch (@typeInfo(T)) {
        .int => @divTrunc(self.data, 256),
        .float => @as(T, @floatFromInt(self.data)) / 256.0,
        else => @compileError("expected a float or int type for Fixed.to"),
    };
}
