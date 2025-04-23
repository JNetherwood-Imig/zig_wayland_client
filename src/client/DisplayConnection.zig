gpa: Allocator,
socket: Socket,
id_allocator: IdAllocator,
proxy: wl.Display,
event_queue: EventQueue,
cancel_pipe: Pipe,
event_thread: Thread,

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
    EventQueue.InitError ||
    Pipe.CreateError ||
    Thread.SpawnError;

pub fn init(gpa: Allocator, connect_info: anytype) InitError!*DisplayConnection {
    const self = try gpa.create(DisplayConnection);
    errdefer gpa.destroy(self);

    self.gpa = gpa;
    self.socket = try connect(connect_info);
    self.id_allocator = IdAllocator.init(gpa);
    self.proxy = wl.Display{};
    self.event_queue = try EventQueue.init();
    self.cancel_pipe = try Pipe.create();
    self.event_thread = try Thread.spawn(.{ .allocator = self.gpa }, pollEvents, .{self});

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
    self.gpa.destroy(self);
}

pub fn waitNextEvent(self: *DisplayConnection) ?wl.Event {
    return self.event_queue.wait();
}

pub fn getNextEvent(self: *DisplayConnection) ?wl.Event {
    return self.event_queue.get();
}

const ConnectError = error{
    InvalidSocketFd,
    NoXdgRuntimeDir,
    SocketPathTooLong,
} || GetConnectInfoError || Socket.CreateError || Socket.ConnectUnixError;

fn connect(connect_info: anytype) ConnectError!Socket {
    return if (@TypeOf(connect_info) == Socket)
        connect_info
    else if (@TypeOf(connect_info) == File)
        Socket{ .handle = connect_info }
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

fn connectToSocket(sockfd: i32) !Socket {
    const socket = Socket{ .handle = .{ .handle = sockfd } };
    var flags = socket.handle.getFlags() catch
        return error.InvalidSocketFd;
    flags.cloexec = true;
    socket.handle.setFlags(flags) catch unreachable;
    return socket;
}

fn connectToDisplay(display: []const u8) !Socket {
    const socket = try Socket.create(.unix, .stream, .{ .cloexec = true }, null);
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
    var pfds = [_]posix.Pollfd{ .{
        .fd = self.socket.handle,
        .events = .{ .in = true },
    }, .{
        .fd = self.cancel_pipe.getReadFile(),
        .events = .{ .in = true },
    } };

    while (true) {
        _ = try posix.poll(&pfds, -1);
        for (&pfds) |*pfd| {
            if (@as(u16, @bitCast(pfd.revents)) != 0) {
                pfd.revents = .{};
                if (pfd.fd == self.cancel_pipe.getReadFile()) return;
                if (pfd.fd == self.socket.handle) try parseEvent(self);
            }
        }
    }
}

// TODO move to serialization api
const Header = packed struct(u64) {
    object: u32,
    opcode: u16,
    length: u16,
};

fn parseEvent(self: *DisplayConnection) !void {
    var head: Header = undefined;
    _ = try self.socket.handle.toStdFile().read(@as(
        [*]u8,
        @ptrCast(@alignCast(&head)),
    )[0..@sizeOf(Header)]);
    const buf = try self.gpa.alloc(
        u8,
        head.length - @sizeOf(Header),
    );
    defer self.gpa.free(buf);
    _ = try self.socket.handle.toStdFile().read(buf);

    // TEMP
    if (head.object == 2 and head.opcode == 0)
        self.event_queue.emplace(.{ .registry_global = undefined });
}

const DisplayConnection = @This();

const std = @import("std");
const Allocator = std.mem.Allocator;
const Thread = std.Thread;
const wl = @import("client_protocol");
const EventQueue = @import("EventQueue.zig");
const IdAllocator = @import("../common/IdAllocator.zig");
const posix = @import("util").posix;
const Pipe = posix.Pipe;
const Socket = posix.Socket;
const File = posix.File;
const Proxy = @import("Proxy.zig");
const testing = std.testing;
