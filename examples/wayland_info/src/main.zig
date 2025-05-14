const std = @import("std");
const wl = @import("wayland_client");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const disp = try wl.DisplayConnection.init(gpa.allocator(), {});
    defer disp.deinit();
}
