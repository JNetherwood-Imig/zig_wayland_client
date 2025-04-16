const std = @import("std");
const wl = @import("wayland_client");
const util = @import("wayland_util");
const io = util.io;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();

    const disp = try wl.DisplayConnection.init(alloc, null);
    defer disp.deinit();

    while (disp.getNextEvent()) |ev| switch (ev) {
        .registry_global => io.eprintln("Recieved registry global"),
        .registry_global_remove => io.eprintln("Recieved registry global remove"),
        else => {},
    };
}
