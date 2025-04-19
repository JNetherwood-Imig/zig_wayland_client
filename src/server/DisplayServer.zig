gpa: Allocator,
socket: posix.Socket,

pub const InitError = Allocator.Error;

pub fn init(gpa: Allocator, setup_info: anytype) InitError!*Self {
    var self = try gpa.create(Self);
    self.gpa = gpa;

    switch (@typeInfo(@TypeOf(setup_info))) {
        // posix.File
        // i32,
        // []u8,
        // [_:0]u8
        // null
        else => @compileError("Unsupported type"),
    }

    return self;
}

pub fn deinit(self: *const Self) void {
    // self.socket.close();
    self.gpa.destroy(self);
}

pub fn getSocket(self: *const Self) posix.File {
    return self.socket.handle;
}

const Self = @This();
const std = @import("std");
const Allocator = std.mem.Allocator;
const posix = @import("util").posix;
