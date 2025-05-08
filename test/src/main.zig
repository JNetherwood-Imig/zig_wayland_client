const std = @import("std");
const wl = @import("wayland_client");

const State = struct {
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
                if (std.mem.eql(u8, g.interface, "wl_compositor")) {
                    self.compositor = try self.registry.bind(g.name, wl.Compositor, 6);
                }
                g.deinit();
            },
            .callback_done => break,
            else => unreachable,
        };

        return self;
    }

    pub fn run(self: State) !void {
        _ = try self.display.sync();
        while (self.display.waitNextEvent()) |event| {
            switch (event) {
                .callback_done => |done| {
                    std.debug.print("done event: {any}\n", .{done});
                    break;
                },
                else => unreachable,
            }
            event.deinit();
        }
        _ = try self.display.sync();
        while (self.display.waitNextEvent()) |event| {
            switch (event) {
                .callback_done => |done| {
                    std.debug.print("done event: {any}\n", .{done});
                    break;
                },
                else => unreachable,
            }
            event.deinit();
        }
    }

    pub fn deinit(self: State) void {
        self.display.deinit();
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();

    var state = try State.init(alloc);
    defer state.deinit();

    try state.run();
}
