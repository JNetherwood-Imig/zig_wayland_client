const builtin = @import("builtin");
const std = @import("std");
const wl = @import("wayland_client");
const util = @import("wayland_util");
const io = util.io;

const gpa = struct {
    var internal = std.heap.GeneralPurposeAllocator(.{}){};
    pub const allocator = switch (builtin.mode) {
        .ReleaseFast => std.heap.smp_allocator,
        else => internal.allocator(),
    };

    pub fn deinit() void {
        switch (builtin.mode) {
            .ReleaseFast => {},
            else => _ = internal.deinit(),
        }
    }
};

pub fn main() !void {
    const alloc = gpa.allocator;
    defer gpa.deinit();

    const disp = try wl.DisplayConnection.init(alloc, null);
    defer disp.deinit();

    while (disp.getNextEvent()) |ev| switch (ev) {
        .registry_global => io.eprintln("Recieved registry global"),
        .registry_global_remove => io.eprintln("Recieved registry global remove"),
        else => {},
    };
}
