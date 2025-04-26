const std = @import("std");
const wl = @import("wayland_client");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();

    const disp = try wl.DisplayConnection.init(alloc, {});
    defer disp.deinit();
    const reg = try disp.getRegistry();
    _ = reg;

    while (disp.waitNextEvent()) |ev| switch (ev) {
        .registry_global => |g| {
            std.debug.print("{d}: {s} ({d})\n", .{ g.name, g.interface, g.version });
            disp.gpa.free(g.interface);
        },
        .registry_global_remove => std.debug.print("Recieved registry global remove\n", .{}),
        else => |event| std.debug.panic("Unexpected wl event recieved: {s}\n", .{@tagName(event)}),
    };
}
