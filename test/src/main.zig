const wl = @import("wayland_client");
const std = @import("std");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();

    var display = try wl.Display.connect(alloc);
    defer display.disconnect();
    _ = try display.getRegistry();

    while (try display.getNextEvent()) |ev| {
        switch (ev) {
            // .wl_registry_global => |g| std.debug.print("{d}: {s} (version {d})\n", .{ g.name, g.interface, g.version }),
            else => continue,
        }
    }
}
