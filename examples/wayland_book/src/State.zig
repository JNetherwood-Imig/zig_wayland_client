const std = @import("std");
const wl = @import("wayland_client");
const shm = @import("shm");

const State = @This();

gpa: std.mem.Allocator,
display: *wl.DisplayConnection,
registry: wl.Registry,
shm: wl.Shm,
shm_pool: wl.ShmPool,
compositor: wl.Compositor,
surface: wl.Surface,
xdg_shell: wl.XdgWmBase,
xdg_surface: wl.XdgSurface,
xdg_toplevel: wl.XdgToplevel,

pub fn init(gpa: std.mem.Allocator) !State {
    var self: State = undefined;
    self.gpa = gpa;

    self.display = try wl.DisplayConnection.init(gpa, {});
    self.registry = try self.display.getRegistry();
    _ = try self.display.sync();

    while (self.display.waitNextEvent()) |ev| switch (ev) {
        .registry_global => |g| {
            defer g.deinit();
            if (matchGlobal(g, wl.Compositor)) {
                self.compositor = try self.registry.bind(g.name, wl.Compositor, 6);
                self.surface = try self.compositor.createSurface();
                continue;
            }
            if (matchGlobal(g, wl.Shm)) {
                self.shm = try self.registry.bind(g.name, wl.Shm, 1);
                continue;
            }
            if (matchGlobal(g, wl.XdgWmBase)) {
                self.xdg_shell = try self.registry.bind(g.name, wl.XdgWmBase, 6);
                continue;
            }
        },
        .callback_done => break,
        else => unreachable,
    };

    return self;
}

pub fn run(self: State) !void {
    _ = try self.display.sync();
    while (self.display.waitNextEvent()) |ev| switch (ev) {
        .callback_done => break,
        else => unreachable,
    };
}

pub fn deinit(self: State) void {
    self.display.deinit();
}

inline fn matchGlobal(global: wl.Registry.GlobalEvent, comptime Interface: type) bool {
    return std.mem.eql(u8, global.interface, Interface.interface);
}

fn randName(buf: []u8) void {
    const ts = std.posix.clock_gettime(std.posix.CLOCK.MONOTONIC) catch unreachable;
    var r = ts.nsec;
    for (0..buf.len) |i| {
        buf[i] = 'A' + (r & 15) + (r & 16) * 2;
        r >>= 5;
    }
}

fn sharedMemoryFile() std.fs.File.Handle {
    const SharedI32 = shm.SharedMemory([]i32);
    for (0..100) |_| {}
}
