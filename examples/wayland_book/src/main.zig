const std = @import("std");
const State = @import("State.zig");

pub fn main() !void {
    var state = try State.init(std.heap.smp_allocator);
    defer state.deinit();
    try state.run();
}
