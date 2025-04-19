gpa: Allocator,
socket: Socket,

pub const ConnectInfo = union(enum) {
    socket: i32,
    display: []const u8,
};

pub fn getConnectInfo() ConnectInfo {
    if (std.posix.getenv("WAYLAND_SOCKET")) |wayland_socket| {
        const socket = std.fmt.parseInt(i32, wayland_socket, 10) catch null;
        if (socket) |sock| return .{ .socket = sock };
    }
    const wayland_display = std.posix.getenv("WAYLAND_DISPLAY");
    return .{ .display = wayland_display orelse "wayland-0" };
}

pub const InitError = Allocator.Error || ConnectError;

pub fn init(gpa: Allocator, connect_info: anytype) InitError!*Self {
    const self = try gpa.create(Self);

    self.gpa = gpa;
    self.socket = try connectSocket(connect_info);

    return self;
}

pub fn terminate(self: *const Self) void {
    _ = self;
}

pub fn deinit(self: *const Self) void {
    self.terminate();
    self.socket.close();
    self.gpa.destroy(self);
}

pub fn getNextEvent(self: *const Self) ?wl.Event {
    _ = self;
    return null;
}

const ConnectError = error{
    NoXdgRuntimeDir,
    SocketPathTooLong,
} || Socket.CreateError;

fn connectSocket(connect_info: anytype) ConnectError!Socket {
    if (@TypeOf(connect_info) == Socket) return connect_info;
    if (@TypeOf(connect_info) == File) return .{ .handle = connect_info };
    const info = if (@TypeOf(connect_info) == ConnectInfo)
        connect_info
    else switch (@typeInfo(@TypeOf(connect_info))) {
        .int, .comptime_int => ConnectInfo{ .socket = @intCast(connect_info) },
        .array => ConnectInfo{ .display = @ptrCast(&connect_info) },
        .pointer => ConnectInfo{ .display = @ptrCast(connect_info) },
        .null => getConnectInfo(),
        else => @compileError("Unsupported type"),
    };
    return switch (info) {
        .socket => |socket| Socket{ .handle = File{ .handle = socket } },
        .display => |display| init: {
            const sock = try Socket.create(
                .unix,
                .stream,
                .{ .cloexec = true },
                null,
            );
            // TODO make separate function
            const xdg_runtime_dir = std.posix.getenv("XDG_RUNTIME_DIR") orelse
                return error.NoXdgRuntimeDir;
            var buf: [108]u8 = @splat(0);
            const path = if (std.fs.path.isAbsolute(display))
                display
            else
                std.fmt.bufPrint(
                    &buf,
                    "{s}/{s}",
                    .{ xdg_runtime_dir, display },
                ) catch
                    return error.SocketPathTooLong;
            try sock.connectUnix(path);
            break :init sock;
        },
    };
}

const Self = @This();

const std = @import("std");
const Allocator = std.mem.Allocator;
const posix = @import("util").posix;
const Socket = posix.Socket;
const File = posix.File;
const wl = @import("client_protocol");
