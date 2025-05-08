gpa: Allocator,
socket: os.Socket,
id_allocator: IdAllocator,
objects: std.ArrayList(wl.Proxy),
proxy: wl.Display,
event_queue: EventQueue,
cancel_pipe: os.Pipe,
event_thread: std.Thread,

pub const ConnectInfo = union(enum) {
    socket: i32,
    display: []const u8,
};

pub const GetConnectInfoError = error{MalformedWaylandSocket};

pub fn getConnectInfo() GetConnectInfoError!ConnectInfo {
    if (std.posix.getenv("WAYLAND_SOCKET")) |wayland_socket| {
        const socket = std.fmt.parseInt(i32, wayland_socket, 10) catch
            return error.MalformedWaylandSocket;
        return ConnectInfo{ .socket = socket };
    }
    const wayland_display = std.posix.getenv("WAYLAND_DISPLAY") orelse "wayland-0";
    return ConnectInfo{ .display = wayland_display };
}

pub const InitError = Allocator.Error ||
    ConnectError ||
    os.Pipe.CreateError ||
    std.Thread.SpawnError;

pub fn init(gpa: Allocator, connect_info: anytype) InitError!*DisplayConnection {
    const self = try gpa.create(DisplayConnection);
    errdefer gpa.destroy(self);

    self.gpa = gpa;
    self.socket = try connect(connect_info);
    self.id_allocator = IdAllocator.init(gpa);
    self.objects = try std.ArrayList(wl.Proxy).initCapacity(gpa, 4);
    self.proxy = wl.Display{
        .proxy = .{
            .id = 1,
            .event0_index = 0,
            .socket = self.socket.handle,
            .id_allocator = &self.id_allocator,
            .object_list = &self.objects,
            .gpa = gpa,
        },
    };
    self.event_queue = EventQueue.init();
    self.cancel_pipe = try os.Pipe.create();
    self.event_thread = try std.Thread.spawn(.{ .allocator = self.gpa }, pollEvents, .{self});
    try self.objects.append(self.proxy.proxy);

    return self;
}

pub fn deinit(self: *DisplayConnection) void {
    self.cancel_pipe.writeAll("1") catch {};
    self.event_queue.cancel();
    self.event_thread.join();
    self.cancel_pipe.close();
    self.event_queue.deinit();
    self.id_allocator.deinit();
    self.socket.close();
    self.objects.deinit();
    self.gpa.destroy(self);
}

pub fn waitNextEvent(self: *DisplayConnection) ?wl.Event {
    return self.event_queue.wait();
}

pub fn getNextEvent(self: *DisplayConnection) ?wl.Event {
    return self.event_queue.get();
}

pub fn sync(self: DisplayConnection) !wl.Callback {
    return self.proxy.sync();
}

pub fn getRegistry(self: DisplayConnection) !wl.Registry {
    return self.proxy.getRegistry();
}

const ConnectError = error{
    InvalidSocketFd,
    NoXdgRuntimeDir,
    SocketPathTooLong,
} || GetConnectInfoError || os.Socket.CreateError || os.Socket.ConnectUnixError;

fn connect(connect_info: anytype) ConnectError!os.Socket {
    return if (@TypeOf(connect_info) == os.Socket)
        connect_info
    else if (@TypeOf(connect_info) == os.File)
        os.Socket{ .handle = connect_info }
    else switch (try connectInfoFromAny(connect_info)) {
        .socket => |sockfd| try connectToSocket(sockfd),
        .display => |display| try connectToDisplay(display),
    };
}

inline fn connectInfoFromAny(connect_info: anytype) !ConnectInfo {
    return if (@TypeOf(connect_info) == ConnectInfo)
        connect_info
    else switch (@typeInfo(@TypeOf(connect_info))) {
        .int, .comptime_int => ConnectInfo{ .socket = @intCast(connect_info) },
        .array => ConnectInfo{ .display = @ptrCast(&connect_info) },
        .pointer => ConnectInfo{ .display = @ptrCast(connect_info) },
        .void => try getConnectInfo(),
        else => @compileError("Unsupported type for DisplayConnection.init"),
    };
}

fn connectToSocket(sockfd: i32) !os.Socket {
    const socket = os.Socket{ .handle = .{ .handle = sockfd } };
    var flags = socket.handle.getFlags() catch
        return error.InvalidSocketFd;
    flags.cloexec = true;
    socket.handle.setFlags(flags) catch unreachable;
    return socket;
}

fn connectToDisplay(display: []const u8) !os.Socket {
    const socket = try os.Socket.create(.unix, .stream, .{ .cloexec = true }, null);
    const xdg_runtime_dir = std.posix.getenv("XDG_RUNTIME_DIR") orelse
        return error.NoXdgRuntimeDir;

    if (std.fs.path.isAbsolute(display)) {
        try socket.connectUnix(display);
    } else {
        var buf: [108]u8 = @splat(0);
        const path = std.fmt.bufPrint(&buf, "{s}/{s}", .{ xdg_runtime_dir, display }) catch
            return error.SocketPathTooLong;
        try socket.connectUnix(path);
    }

    return socket;
}

fn pollEvents(self: *DisplayConnection) !void {
    var pfds = [_]os.Pollfd{ .{
        .fd = self.socket.handle,
        .events = .{ .in = true },
    }, .{
        .fd = self.cancel_pipe.getReadFile(),
        .events = .{ .in = true },
    } };

    while (true) {
        _ = try os.poll(&pfds, -1);
        for (&pfds) |*pfd| {
            if (@as(u16, @bitCast(pfd.revents)) != 0) {
                pfd.revents = .{};
                if (pfd.fd == self.cancel_pipe.getReadFile()) return;
                if (pfd.fd == self.socket.handle) try recieveEvent(self);
            }
        }
    }
}

fn recieveEvent(self: *DisplayConnection) !void {
    var head: Header = undefined;
    _ = try self.socket.handle.read(std.mem.asBytes(&head));

    const proxy = for (self.objects.items) |obj| {
        if (obj.id == head.object) break obj;
    } else {
        std.debug.print("Could not find object id {d}\n", .{head.object});
        std.debug.print("Have ids:\n", .{});
        for (self.objects.items) |obj| {
            std.debug.print("\t{d}\n", .{obj.id});
        }
        unreachable;
    };

    const event = try proxy.parseEvent(head);
    switch (event) {
        .display_error => |err| {
            std.debug.panic("wl_display_error\n\tobject_id: {d}\n\tcode: {s}\n\tmessage: {s}\n", .{
                err.object_id,
                @tagName(@as(wl.Display.Error, @enumFromInt(err.code))),
                err.message,
            });
        },
        .display_delete_id => |delete_id| {
            std.debug.print("RECIEVED DELETE ID ({d})\n", .{delete_id.id});
            for (self.objects.items, 0..) |obj, i| {
                if (obj.id == delete_id.id) {
                    _ = self.objects.swapRemove(i);
                    try self.id_allocator.free(obj.id);
                    return;
                }
            }
        },
        else => self.event_queue.emplace(event),
    }
}

const DisplayConnection = @This();

const std = @import("std");
const wl = @import("client_protocol");
const os = @import("os");
const common = @import("common");
const m = common.message_utils;
const testing = std.testing;
const roundup4 = m.roundup4;
const IdAllocator = common.IdAllocator;
const EventQueue = @import("EventQueue.zig");
const Allocator = std.mem.Allocator;
const Header = m.Header;
