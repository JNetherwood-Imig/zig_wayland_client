gpa: Allocator,

pub const InitError = Allocator.Error;

pub fn init(gpa: Allocator, setup_info: anytype) InitError!*DisplayServer {
    var self = try gpa.create(DisplayServer);
    self.gpa = gpa;

    switch (@typeInfo(@TypeOf(setup_info))) {
        .int => {},
        .void => {},
        else => @compileError("Unsupported type"),
    }

    return self;
}

pub fn deinit(self: *const DisplayServer) void {
    self.gpa.destroy(self);
}

fn createSocket() void {}

const DisplayServer = @This();

const std = @import("std");
const Allocator = std.mem.Allocator;
