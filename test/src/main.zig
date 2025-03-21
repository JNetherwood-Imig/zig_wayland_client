const wl = @import("wayland_client");
const std = @import("std");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();

    var display = try wl.Display.connect();
    defer display.disconnect();
    const registry = try display.getRegistry();
    const compositor = try registry.bind(2, wl.Compositor, 6);
    const region = try compositor.createRegion();
    defer region.destroy();
    try region.subtract(1, 2, 3, 4);

    while (display.getNextEvent(alloc)) |ev| {
        switch (ev) {
            .wl_registry_global => |g| {
                std.debug.print("Registry global => {d}: {s} (version {d})\n", .{
                    g.name,
                    g.interface,
                    g.version,
                });
                alloc.free(g.interface);
            },
            else => continue,
        }
    }
}
