const std = @import("std");
const State = @import("State.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();

    var state = try State.init(alloc);
    defer state.deinit();

    try state.run();
}
