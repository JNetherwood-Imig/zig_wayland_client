gpa: Allocator,

pub const InitError = Allocator.Error;

pub fn init(gpa: Allocator, setup_info: anytype) InitError!*DisplayServer {
    _ = setup_info;
    var self = try gpa.create(DisplayServer);
    self.gpa = gpa;

    return self;
}

pub fn deinit(self: *const DisplayServer) void {
    self.gpa.destroy(self);
}

const DisplayServer = @This();

const std = @import("std");
const Allocator = std.mem.Allocator;
