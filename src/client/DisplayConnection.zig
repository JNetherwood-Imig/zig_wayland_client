const std = @import("std");
const Allocator = std.mem.Allocator;

const Connection = @import("Connection.zig");
const EventLoop = @import("../common/EventLoop.zig");
const EventQueue = @import("EventQueue.zig");

const sys_utils = @import("../common/sys_utils.zig");
const Sig = sys_utils.Sig;

const wl = @import("client_protocol");

const Self = @This();

allocator: Allocator,
display: wl.Display,
connection: Connection,
event_loop: EventLoop,
event_queue: EventQueue,

pub fn getConnectInfo() Connection.ConnectInfo {
    if (std.posix.getenv("WAYLAND_SOCKET")) |wayland_socket| {
        const socket = std.fmt.parseInt(std.posix.socket_t, wayland_socket, 10) catch null;
        if (socket) |sock| return .{ .socket = sock };
    }
    return .{ .display = std.posix.getenv("WAYLAND_DISPLAY") orelse "wayland-0" };
}

pub const Error = Allocator.Error ||
    Connection.Error ||
    EventLoop.Error ||
    EventLoop.AddFdError ||
    EventLoop.AddSignalsError ||
    EventLoop.StartError;

pub fn init(allocator: Allocator, connect_info: anytype) Error!*Self {
    const info: Connection.ConnectInfo = if (@TypeOf(connect_info) == Connection.ConnectInfo)
        connect_info
    else switch (@typeInfo(@TypeOf(connect_info))) {
        .comptime_int, .int => .{ .socket = @intCast(connect_info) },
        .pointer => |ptr| init: {
            _ = ptr;
            break :init .{ .display = @ptrCast(connect_info) };
        },
        .null => getConnectInfo(),
        else => @compileError("Invalid type"),
    };

    const self = try allocator.create(Self);
    self.* = Self{
        .allocator = allocator,
        .display = undefined,
        .connection = try Connection.init(info),
        .event_loop = try EventLoop.init(allocator),
        .event_queue = try EventQueue.init(),
    };

    try self.event_loop.start();

    try self.event_loop.addFd(
        self.connection.socket.handle,
        .{ .readable = true },
        &handleEvents,
        self,
    );

    try self.event_loop.addSignals(.{
        .interrupt = true,
        .quit = true,
        .terminated = true,
        .user_1 = true,
        .user_2 = true,
    }, &handleSignals, self);

    return self;
}

pub fn terminate(self: Self) void {
    self.event_queue.cancelRead();
    self.event_loop.terminate();
}

pub fn deinit(self: *Self) void {
    self.event_queue.deinit();
    self.event_loop.deinit();
    self.connection.deinit();
    self.allocator.destroy(self);
}

pub fn getNextEvent(self: *Self) ?wl.Event {
    return self.event_queue.pop();
}

fn handleEvents(_: EventLoop.EventMask, data: ?*anyopaque) !void {
    const self: *Self = @ptrCast(@alignCast(data.?));
    _ = self;
    // TODO read socket for event
    // push wl.Event to event queue and assert that it works
}

fn handleSignals(signal: Sig, data: ?*anyopaque) !void {
    const self: *Self = @ptrCast(@alignCast(data.?));
    switch (signal) {
        .user_1 => {
            try self.event_queue.push(.{ .registry_global = undefined });
        },
        .user_2 => {
            try self.event_queue.push(.{ .registry_global_remove = undefined });
        },
        else => {
            std.log.debug("Recieved {s} signal", .{@tagName(signal)});
            self.terminate();
        },
    }
}
