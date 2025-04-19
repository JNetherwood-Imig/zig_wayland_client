const wl = @import("wayland_client");
const util = @import("wayland_util");
const io = util.io;
const gpa = util.gpa;

pub fn main() !void {
    defer gpa.deinit();

    const disp = try wl.DisplayConnection.init(gpa.allocator, null);
    defer disp.deinit();

    io.eprintln("Initialized!");
    defer io.eprintln("Deinitializing...");

    while (disp.getNextEvent()) |ev| switch (ev) {
        .registry_global => io.eprintln("Recieved registry global"),
        .registry_global_remove => io.eprintln("Recieved registry global remove"),
        else => {},
    };
}
