gpa: Allocator,
socket: os.Socket,
proxy_manager: ProxyManager,
event_queue: EventQueue,
cancel_pipe: os.Pipe,
event_thread: std.Thread,
proxy: wl.Display,

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
    ProxyManager.GetProxyError ||
    std.Thread.SpawnError;

pub fn init(gpa: Allocator, connect_info: anytype) InitError!*DisplayConnection {
    const self = try gpa.create(DisplayConnection);
    errdefer gpa.destroy(self);

    self.gpa = gpa;
    self.socket = try connect(connect_info);
    self.proxy_manager = ProxyManager.init(gpa, self.socket.handle);
    self.proxy = wl.Display{
        .proxy = try self.proxy_manager.getNewProxy(wl.Display),
    };
    self.event_queue = EventQueue.init();
    self.cancel_pipe = try os.Pipe.create();
    self.event_thread = try std.Thread.spawn(.{ .allocator = self.gpa }, pollEvents, .{self});

    return self;
}

pub fn deinit(self: *DisplayConnection) void {
    self.cancel_pipe.writeAll("1") catch {};
    self.event_queue.cancel();
    self.event_thread.join();
    self.cancel_pipe.close();
    self.event_queue.deinit();
    self.proxy_manager.deinit();
    self.socket.close();
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

    const event = try self.parseEvent(head);
    switch (event) {
        .display_error => |err| {
            std.debug.panic("wl_display_error\n\tobject_id: {d}\n\tcode: {s}\n\tmessage: {s}\n", .{
                err.object_id,
                @tagName(@as(wl.Display.Error, @enumFromInt(err.code))),
                err.message,
            });
        },
        .display_delete_id => |delete_id| try self.proxy_manager.deleteId(delete_id.id),
        else => self.event_queue.emplace(event),
    }
}

pub fn parseEvent(self: *DisplayConnection, header: Header) !wl.Event {
    const event0_index = self.proxy_manager.proxy_type_references.items[header.object];
    const tag_name = @tagName(@as(wl.EventType, @enumFromInt(event0_index + header.opcode)));
    inline for (@typeInfo(wl.Event).@"union".fields) |field| {
        if (std.mem.eql(u8, field.name, tag_name)) {
            const union_field_info = field;
            const struct_type = union_field_info.type;
            var struct_value: struct_type = undefined;
            struct_value.self = .{ .proxy = .{
                .id = header.object,
                .gpa = self.gpa,
                .event0_index = event0_index,
                .manager = &self.proxy_manager,
                .socket = self.socket.handle,
            } };

            const fd_count = count: {
                comptime var count: usize = 0;
                inline for (@typeInfo(struct_type).@"struct".fields) |s_field| {
                    if (@TypeOf(s_field) == os.File) count += 1;
                }
                break :count count;
            };

            const buf = try self.gpa.alloc(u8, header.length - @sizeOf(Header));
            defer self.gpa.free(buf);

            var fds: [fd_count]os.File = undefined;
            _ = try self.socket.handle.recieveMessage(@TypeOf(fds), &fds, buf, 0);

            var index: usize = 0;
            var fd_idx: usize = 0;

            inline for (@typeInfo(struct_type).@"struct".fields) |s_field| {
                if (comptime std.mem.eql(u8, s_field.name, "self")) continue;
                switch (s_field.type) {
                    u32 => {
                        @field(struct_value, s_field.name) = std.mem.bytesToValue(u32, buf[index .. index + 4]);
                        index += 4;
                    },
                    i32 => {
                        @field(struct_value, s_field.name) = std.mem.bytesToValue(i32, buf[index .. index + 4]);
                        index += 4;
                    },
                    Array => {
                        const len = std.mem.bytesToValue(u32, buf[index .. index + 4]);
                        index += 4;
                        const rounded_len = roundup4(len);
                        @field(struct_value, s_field.name) = try self.gpa.dupe(u8, buf[index .. index + len]);
                        index += rounded_len;
                    },
                    String => {
                        const len = std.mem.bytesToValue(u32, buf[index .. index + 4]);
                        index += 4;
                        const rounded_len = roundup4(len);
                        @field(struct_value, s_field.name) = try self.gpa.dupeZ(u8, buf[index .. index + len - 1]);
                        index += rounded_len;
                    },
                    os.File => {
                        if (fd_count > 0) {
                            @field(struct_value, s_field.name) = fds[fd_idx];
                            fd_idx += 1;
                        }
                    },
                    else => std.debug.panic("Unexpected type: {s}", .{@typeName(s_field.type)}),
                }
            }
            return @unionInit(wl.Event, union_field_info.name, struct_value);
        }
    }
    unreachable;
}

const DisplayConnection = @This();

const std = @import("std");
const wl = @import("wayland_client_protocol");
const os = @import("os");
const core = @import("core");
const m = core.message_utils;
const testing = std.testing;
const roundup4 = m.roundup4;
const ProxyManager = core.ProxyManager;
const Proxy = core.Proxy;
const EventQueue = @import("EventQueue.zig");
const Allocator = std.mem.Allocator;
const Header = m.Header;
const Array = m.Array;
const String = m.String;
