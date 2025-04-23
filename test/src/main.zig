const std = @import("std");
const wl = @import("wayland_client");

pub fn main() !void {
    const disp = try wl.DisplayConnection.init(std.heap.page_allocator, {});
    defer disp.deinit();

    std.debug.print("OK\n", .{});

    while (disp.waitNextEvent()) |ev| switch (ev) {
        .registry_global => std.debug.print("Recieved registry global\n", .{}),
        .registry_global_remove => std.debug.print("Recieved registry global remove\n", .{}),
        else => {},
    };
}
