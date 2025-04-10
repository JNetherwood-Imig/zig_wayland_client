const std = @import("std");
const wl = @import("wayland_client");

pub fn main() !void {
    const disp = try wl.DisplayConnection.init(null);
    defer disp.deinit();
    std.log.info("OK", .{});
}
