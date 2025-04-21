gpa: Allocator,
socket: Socket,
event_queue: EventQueue,
id_allocator: IdAllocator,
event_thread: Thread,
cancel_pipe: Pipe,
proxy: if (@hasDecl(wl, "Display")) wl.Display else void,

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

pub const InitError = Allocator.Error ||
    ConnectError ||
    EventQueue.InitError ||
    Thread.SpawnError ||
    Pipe.CreateError;

pub fn init(gpa: Allocator, connect_info: anytype) InitError!*DisplayConnection {
    const self = try gpa.create(DisplayConnection);

    self.gpa = gpa;
    self.socket = try connectSocket(connect_info);
    self.event_queue = try EventQueue.init();
    self.id_allocator = IdAllocator.init(gpa);
    self.cancel_pipe = try Pipe.create();
    self.event_thread = try Thread.spawn(.{ .allocator = gpa }, pollEvents, .{self});
    // self.proxy = wl.Display{
    //     .proxy = Proxy{
    //         .id = 1,
    //         .event0_index = 0,
    //         .socket = self.socket,
    //         .id_allocator = &self.id_allocator,
    //     },
    // };

    return self;
}

pub fn terminate(self: *DisplayConnection) void {
    self.cancel_pipe.writeAll("1") catch return;
    self.event_queue.cancel();
}

pub fn deinit(self: *DisplayConnection) void {
    self.terminate();
    self.event_thread.join();
    self.cancel_pipe.close();
    self.id_allocator.deinit();
    self.event_queue.deinit();
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
    NoXdgRuntimeDir,
    SocketPathTooLong,
} || Socket.CreateError || Socket.ConnectUnixError;

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
        .display => |display| try connectToDisplay(display),
    };
}

fn connectToDisplay(display: []const u8) !Socket {
    const socket = try Socket.create(.unix, .stream, .{ .cloexec = true }, null);
    const xdg_runtime_dir = std.posix.getenv("XDG_RUNTIME_DIR") orelse
        return error.NoXdgRuntimeDir;
    var buf: [108]u8 = @splat(0);
    const path = if (std.fs.path.isAbsolute(display))
        display
    else
        std.fmt.bufPrint(&buf, "{s}/{s}", .{ xdg_runtime_dir, display }) catch
            return error.SocketPathTooLong;
    try socket.connectUnix(path);
    return socket;
}

fn pollEvents(self: *DisplayConnection) !void {
    var pfds = [_]posix.Pollfd{
        posix.Pollfd{
            .fd = self.socket.handle,
            .events = .{ .in = true },
        },
        posix.Pollfd{
            .fd = self.cancel_pipe.getReadFile(),
            .events = .{ .in = true },
        },
    };

    while (true) {
        _ = try posix.poll(&pfds, -1);
        for (&pfds) |*pfd| {
            if (@as(u16, @bitCast(pfd.revents)) != 0) {
                pfd.revents = .{};
                if (pfd.fd == self.cancel_pipe.getReadFile()) {
                    var buf: [1]u8 = undefined;
                    _ = try self.cancel_pipe.read(&buf);
                    return;
                }
                if (pfd.fd == self.socket.handle) {
                    var head: Header = undefined;
                    _ = try self.socket.handle.toStdFile().read(@as([*]u8, @ptrCast(@alignCast(&head)))[0..@sizeOf(Header)]);
                    std.debug.print("Server event detected: {any}", .{head});
                    const buf = try self.gpa.alloc(u8, head.length - @sizeOf(Header));
                    defer self.gpa.free(buf);
                    _ = try self.socket.handle.toStdFile().read(buf);
                    if (head.object == 2 and head.opcode == 0)
                        self.event_queue.emplace(.{ .registry_global = undefined });
                }
            }
        }
    }
}

const Header = packed struct(u64) {
    object: u32,
    opcode: u16,
    length: u16,
};
const DisplayConnection = @This();

const std = @import("std");
const Allocator = std.mem.Allocator;
const Thread = std.Thread;
const wl = @import("client_protocol");
const EventQueue = @import("EventQueue.zig");
const IdAllocator = @import("../common/IdAllocator.zig");
const posix = @import("../util/posix.zig");
const Socket = posix.Socket;
const File = posix.File;
const Pipe = posix.Pipe;
const Proxy = @import("Proxy.zig");
