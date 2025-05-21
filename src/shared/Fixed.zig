data: i32,

pub fn from(comptime T: type, value: T) Fixed {
    return switch (@typeInfo(T)) {
        .int => Fixed{ .data = @intCast(value * 256) },
        .float => Fixed{ .data = @intFromFloat(value * 256.0) },
        else => @compileError("expected a float or int type for Fixed.from"),
    };
}

pub fn to(self: Fixed, comptime T: type) T {
    return switch (@typeInfo(T)) {
        .int => @intCast(@divTrunc(self.data, 256)),
        .float => @as(T, @floatFromInt(self.data)) / 256.0,
        else => @compileError("expected a float or int type for Fixed.to"),
    };
}

test "from/to" {
    const fix_i32 = Fixed.from(i32, 15);
    const fix_f64 = Fixed.from(f64, 15.0);

    try testing.expectEqual(@as(u16, 15), fix_i32.to(u16));
    try testing.expectEqual(@as(u16, 15), fix_f64.to(u16));

    try testing.expectApproxEqAbs(@as(f32, 15.0), fix_i32.to(f32), 0.001);
    try testing.expectApproxEqAbs(@as(f32, 15.0), fix_f64.to(f32), 0.001);

    try testing.expectApproxEqAbs(fix_i32.to(f64), fix_f64.to(f64), 0.001);
}

const Fixed = @This();
const testing = @import("std").testing;
