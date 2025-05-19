const std = @import("std");
const wl = @import("wayland_client");
const wlkb = @import("wlkb");

const State = @This();

// Assorted app objects
gpa: std.mem.Allocator,
connection: *wl.DisplayConnection,

// Wayland globals
display: wl.Display,
registry: wl.Registry,
compositor: wl.Compositor,
shm: wl.Shm,
xdg_shell: wl.XdgWmBase,
seat: wl.Seat,

// Wayland objects
surface: wl.Surface,
xdg_surface: wl.XdgSurface,
xdg_toplevel: wl.XdgToplevel,
pointer: wl.Pointer,
keyboard: wl.Keyboard,
touch: wl.Touch,

// Data
width: usize,
height: usize,
offset: f32,
last_frame: u32,
pointer_event: PointerEvent,
kb_state: wlkb.State,

pub fn init(gpa: std.mem.Allocator) !State {
    var self: State = undefined;
    self.gpa = gpa;
    self.connection = try wl.DisplayConnection.init(gpa, {});
    self.width = 640;
    self.height = 480;
    self.offset = 0.0;
    self.last_frame = 0;
    self.pointer.proxy.id = 0;
    self.keyboard.proxy.id = 0;
    self.touch.proxy.id = 0;
    self.pointer_event.mask = .{};

    self.display = self.connection.proxy;
    self.registry = try self.display.getRegistry();
    _ = try self.display.sync();

    while (self.connection.waitNextEvent()) |ev| switch (ev) {
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
            if (matchGlobal(g, wl.Seat)) {
                self.seat = try self.registry.bind(g.name, wl.Seat, 9);
                continue;
            }
        },
        else => break,
    };

    self.surface = try self.compositor.createSurface();
    _ = try self.surface.frame();
    self.xdg_surface = try self.xdg_shell.getXdgSurface(self.surface);
    self.xdg_toplevel = try self.xdg_surface.getToplevel();
    try self.xdg_toplevel.setTitle("Hello, Wayland!");
    try self.xdg_toplevel.setAppId("zig_wayland_client");
    try self.surface.commit();

    return self;
}

pub fn run(self: *State) !void {
    while (self.connection.waitNextEvent()) |ev| {
        defer ev.deinit();
        switch (ev) {
            .xdg_toplevel_close => break,
            .xdg_surface_configure => |conf| {
                try self.xdg_surface.ackConfigure(conf.serial);
                const buffer = try self.drawFrame();
                try self.surface.attach(buffer, 0, 0);
                try self.surface.commit();
            },
            .xdg_toplevel_configure => |conf| {
                if (conf.width == 0 and conf.height == 0) continue;

                if (self.width != conf.width or self.height != conf.height) {
                    self.width = @intCast(conf.width);
                    self.height = @intCast(conf.height);
                }
            },
            .xdg_wm_base_ping => |ping| {
                try self.xdg_shell.pong(ping.serial);
            },
            .callback_done => |done| {
                const time = done.callback_data;
                _ = try self.surface.frame();
                if (self.last_frame != 0) {
                    const elapsed = time - self.last_frame;
                    self.offset += @as(f32, @floatFromInt(elapsed)) / @as(f32, 1000.0) * 24;
                }
                const buffer = try self.drawFrame();
                try self.surface.attach(buffer, 0, 0);
                try self.surface.damageBuffer(0, 0, std.math.maxInt(i32), std.math.maxInt(i32));
                try self.surface.commit();
                self.last_frame = time;
            },
            .seat_name => |name| std.debug.print("Seat name: {s}\n", .{name.name}),
            .seat_capabilities => |caps| {
                if (caps.capabilities.pointer and self.pointer.proxy.id == 0) {
                    self.pointer = try self.seat.getPointer();
                } else if (!caps.capabilities.pointer and self.pointer.proxy.id != 0) {
                    self.pointer.release();
                    self.pointer.proxy.id = 0;
                }
                if (caps.capabilities.keyboard and self.keyboard.proxy.id == 0) {
                    self.keyboard = try self.seat.getKeyboard();
                } else if (!caps.capabilities.keyboard and self.keyboard.proxy.id != 0) {
                    self.keyboard.release();
                    self.keyboard.proxy.id = 0;
                }
                if (caps.capabilities.touch and self.touch.proxy.id == 0) {
                    self.touch = try self.seat.getTouch();
                } else if (!caps.capabilities.touch and self.touch.proxy.id != 0) {
                    self.touch.release();
                    self.touch.proxy.id = 0;
                }
            },
            .pointer_enter => |enter| {
                self.pointer_event.mask.enter = true;
                self.pointer_event.serial = enter.serial;
                self.pointer_event.surface_x = enter.surface_x;
                self.pointer_event.surface_y = enter.surface_y;
            },
            .pointer_leave => |leave| {
                self.pointer_event.mask.leave = true;
                self.pointer_event.serial = leave.serial;
            },
            .pointer_motion => |motion| {
                self.pointer_event.mask.motion = true;
                self.pointer_event.time = motion.time;
                self.pointer_event.surface_x = motion.surface_x;
                self.pointer_event.surface_y = motion.surface_y;
            },
            .pointer_button => |button| {
                self.pointer_event.mask.button = true;
                self.pointer_event.serial = button.serial;
                self.pointer_event.time = button.time;
                self.pointer_event.button = button.button;
                self.pointer_event.state = button.state;
            },
            .pointer_axis => |axis| {
                self.pointer_event.mask.axis = true;
                self.pointer_event.time = axis.time;
                self.pointer_event.axes[@intFromEnum(axis.axis)].valid = true;
                self.pointer_event.axes[@intFromEnum(axis.axis)].value = axis.value;
            },
            .pointer_axis_source => |source| {
                self.pointer_event.mask.axis = true;
                self.pointer_event.axis_source = source.axis_source;
            },
            .pointer_axis_stop => |stop| {
                self.pointer_event.mask.axis = true;
                self.pointer_event.time = stop.time;
                self.pointer_event.axes[@intFromEnum(stop.axis)].valid = true;
            },
            .pointer_axis_discrete => |disc| {
                self.pointer_event.mask.axis = true;
                self.pointer_event.axes[@intFromEnum(disc.axis)].valid = true;
                self.pointer_event.axes[@intFromEnum(disc.axis)].discrete = disc.discrete;
            },
            .pointer_axis_value120 => |v120| {
                self.pointer_event.mask.axis_value120 = true;
                self.pointer_event.axes[@intFromEnum(v120.axis)].valid = true;
                self.pointer_event.axes[@intFromEnum(v120.axis)].value120 = v120.value120;
            },
            .pointer_axis_relative_direction => |rel| {
                self.pointer_event.mask.axis_relative_direction = true;
                self.pointer_event.axes[@intFromEnum(rel.axis)].valid = true;
                self.pointer_event.axes[@intFromEnum(rel.axis)].relative_direction = rel.direction;
            },
            .pointer_frame => {
                const pev = self.pointer_event;
                self.pointer_event.mask = .{};
                std.debug.print("Pointer frame: {d}:\n", .{pev.time});

                if (pev.mask.enter)
                    std.debug.print("\tEntered: ({d:.0}, {d:.0})\n", .{ pev.surface_x.to(f64), pev.surface_y.to(f64) });
                if (pev.mask.leave)
                    std.debug.print("\tLeft\n", .{});
                if (pev.mask.motion)
                    std.debug.print("\tMotion: ({d:.0}, {d:.0})\n", .{ pev.surface_x.to(f64), pev.surface_y.to(f64) });
                if (pev.mask.button)
                    std.debug.print("\tButton {d} {s}\n", .{ pev.button, @tagName(pev.state) });

                if (pev.mask.axis or
                    pev.mask.axis_source or
                    pev.mask.axis_stop or
                    pev.mask.axis_discrete or
                    pev.mask.axis_value120 or
                    pev.mask.axis_relative_direction)
                {
                    for (pev.axes, 0..) |axis, i| {
                        if (!axis.valid) continue;

                        std.debug.print("\tAxis ({s}):\n", .{@tagName(@as(wl.Pointer.Axis, @enumFromInt(i)))});
                        if (pev.mask.axis)
                            std.debug.print("\t\tValue: {d}\n", .{axis.value.to(f64)});
                        if (pev.mask.axis_source)
                            std.debug.print("\t\tVia: {s}\n", .{@tagName(pev.axis_source)});
                        if (pev.mask.axis_stop)
                            std.debug.print("\t\tStopped", .{});
                        if (pev.mask.axis_discrete)
                            std.debug.print("\t\tDiscrete: {d}", .{axis.discrete});
                        if (pev.mask.axis_value120)
                            std.debug.print("\t\tValue 120: {d}\n", .{axis.value120});
                        if (pev.mask.axis_relative_direction)
                            std.debug.print("\t\tRelative direction: {s}\n", .{@tagName(axis.relative_direction)});
                    }
                }
            },
            .keyboard_keymap => |keymap| {
                defer keymap.fd.close();
                // TODO handle keymap
            },
            .keyboard_enter => |enter| {
                _ = enter;
                // TODO handle enter
            },
            .keyboard_leave => |leave| {
                _ = leave;
                // TODO handle leave
            },
            .keyboard_key => |key| {
                _ = key;
                // TODO handle key
            },
            .keyboard_modifiers => |mods| {
                _ = mods;
                // TODO handle modifiers
            },
            .keyboard_repeat_info => |rep| {
                _ = rep;
                // TODO handle repeat info
            },
            // TODO handle touch
            else => {},
        }
    }
}

pub fn deinit(self: State) void {
    // c.xkb_context_unref(self.xkb_context);
    self.connection.deinit();
}

fn drawFrame(self: *const State) !wl.Buffer {
    const stride = self.width * 4;
    const size = stride * self.height;

    const fd = try allocateShmFile(size);
    defer fd.close();

    const pool = try self.shm.createPool(fd, @intCast(size));
    defer pool.destroy();
    const buffer = try pool.createBuffer(0, @intCast(self.width), @intCast(self.height), @intCast(stride), .xrgb8888);

    const data = try mapShmFile(u32, fd, size);
    defer unmapShmFile(u32, data);

    const offset = @mod(@as(usize, @intFromFloat(self.offset)), 8);
    for (0..self.height) |y| {
        for (0..self.width) |x| {
            if (((x + offset) + (y + offset) / 8 * 8) % 16 < 8) {
                data[y * self.width + x] = 0xFF666666;
            } else {
                data[y * self.width + x] = 0xFFEEEEEE;
            }
        }
    }

    return buffer;
}

const PointerEvent = struct {
    mask: Mask = .{},
    surface_x: wl.Fixed,
    surface_y: wl.Fixed,
    button: u32,
    state: wl.Pointer.ButtonState,
    time: u32,
    serial: u32,
    axes: [2]struct {
        valid: bool = false,
        value: wl.Fixed = .{ .data = 0 },
        discrete: i32 = 0,
        value120: i32 = 0,
        relative_direction: wl.Pointer.AxisRelativeDirection = .identical,
    },
    axis_source: wl.Pointer.AxisSource,

    const Mask = packed struct {
        enter: bool = false,
        leave: bool = false,
        motion: bool = false,
        button: bool = false,
        axis: bool = false,
        axis_source: bool = false,
        axis_stop: bool = false,
        axis_discrete: bool = false,
        axis_value120: bool = false,
        axis_relative_direction: bool = false,
    };
};

inline fn matchGlobal(global: wl.Registry.GlobalEvent, comptime Interface: type) bool {
    return std.mem.eql(u8, global.interface, Interface.interface);
}

fn allocateShmFile(size: usize) !wl.os.File {
    const fd = try std.posix.memfd_create("wl_shm", 0);
    try std.posix.ftruncate(fd, size);
    return .{ .handle = fd };
}

inline fn mapShmFile(comptime T: type, file: wl.os.File, size: usize) ![]align(4096) T {
    return @ptrCast(@alignCast(try std.posix.mmap(null, size, std.posix.PROT.READ | std.posix.PROT.WRITE, .{ .TYPE = .SHARED }, file.handle, 0)));
}

inline fn unmapShmFile(comptime T: type, data: []align(4096) const T) void {
    std.posix.munmap(@ptrCast(data));
}
