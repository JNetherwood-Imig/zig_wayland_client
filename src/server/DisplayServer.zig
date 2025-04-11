const std = @import("std");
const Self = @This();

stream: std.net.Stream,

pub const Error = error{};

pub fn init(setup_info: anytype) Error!Self {
    switch (@typeInfo(@TypeOf(setup_info))) {
        else => @compileError("Unsupported type"),
    }

    return Self{
        .stream = .{ .handle = -1 },
    };
}

pub fn deinit(self: Self) void {
    self.stream.close();
}
