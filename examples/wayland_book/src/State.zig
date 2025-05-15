const std = @import("std");
const wl = @import("wayland_client");

const State = @This();

gpa: std.mem.Allocator,
display: *wl.DisplayConnection,
registry: wl.Registry,
shm: wl.Shm,
compositor: wl.Compositor,
surface: wl.Surface,
xdg_shell: wl.XdgWmBase,
xdg_surface: wl.XdgSurface,
xdg_toplevel: wl.XdgToplevel,
buffer: wl.Buffer,
frame_callback: wl.Callback,
pixels: []align(std.options.page_size_min orelse 4 << 10) u8,
width: u16,
height: u16,

pub fn init(gpa: std.mem.Allocator) !State {
    var self: State = undefined;
    self.gpa = gpa;
    self.width = 1280;
    self.height = 720;

    self.display = try wl.DisplayConnection.init(gpa, {});
    self.registry = try self.display.getRegistry();
    _ = try self.display.sync();

    while (self.display.waitNextEvent()) |ev| switch (ev) {
        .registry_global => |g| {
            defer g.deinit();
            if (matchGlobal(g, wl.Compositor)) {
                self.compositor = try self.registry.bind(g.name, wl.Compositor, 6);
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
        else => break,
    };

    try self.resizePixelBuffer();
    self.surface = try self.compositor.createSurface();
    self.frame_callback = try self.surface.frame();
    self.xdg_surface = try self.xdg_shell.getXdgSurface(self.surface);
    self.xdg_toplevel = try self.xdg_surface.getToplevel();
    try self.xdg_toplevel.setTitle("Hello, Wayland!");
    try self.surface.commit();

    return self;
}

pub fn run(self: *State) !void {
    while (self.display.waitNextEvent()) |ev| {
        defer ev.deinit();
        switch (ev) {
            .callback_done => try self.frame_new(),
            .xdg_toplevel_configure => |conf| {
                if (conf.width == 0 and conf.height == 0) continue;
                if (self.width != conf.width or self.height != conf.height) {
                    std.posix.munmap(self.pixels);
                    self.width = @intCast(conf.width);
                    self.height = @intCast(conf.height);
                    try self.resizePixelBuffer();
                }
            },
            .xdg_surface_configure => |conf| {
                try self.xdg_surface.ackConfigure(conf.serial);
                if (self.pixels.len == 0) try self.resizePixelBuffer();
                try self.draw();
            },
            .xdg_wm_base_ping => |ping| {
                try self.xdg_shell.pong(ping.serial);
            },
            .xdg_toplevel_close => break,
            else => {},
        }
    }
}

pub fn deinit(self: State) void {
    self.display.deinit();
}

inline fn matchGlobal(global: wl.Registry.GlobalEvent, comptime Interface: type) bool {
    return std.mem.eql(u8, global.interface, Interface.interface);
}

fn allocateShmFile(size: usize) !wl.os.File {
    const fd = try std.posix.memfd_create("wl_shm", 0);
    try std.posix.ftruncate(fd, size);
    return .{ .handle = fd };
}

fn resizePixelBuffer(self: *State) !void {
    const size: usize = @as(usize, self.width) * @as(usize, self.height) * 4;
    const fd = try allocateShmFile(size);
    self.pixels = try std.posix.mmap(
        null,
        size,
        std.posix.PROT.READ | std.posix.PROT.WRITE,
        .{ .TYPE = .SHARED },
        fd.handle,
        0,
    );

    const pool = try self.shm.createPool(fd, @intCast(size));
    self.buffer = try pool.createBuffer(0, self.width, self.height, self.width * 4, .argb8888);
    pool.destroy();
    fd.close();
}

fn draw(self: *State) !void {
    @memset(self.pixels, 0xff);

    try self.surface.attach(self.buffer, 0, 0);
    try self.surface.damageBuffer(0, 0, self.width, self.height);
    try self.surface.commit();
}

fn frame_new(self: *State) !void {
    self.frame_callback = try self.surface.frame();
    try self.draw();
}
