var _gpa: Allocator = undefined;
var socket: os.Socket = undefined;
var proxy_manager: ProxyManager = undefined;
var event_queue: EventQueue = undefined;
var cancel_pipe: os.Pipe = undefined;
var event_thread: std.Thread = undefined;
var display: wl.Display = undefined;

pub const ConnectInfo = union(enum) {
    fd: i32,
    file: os.File,
    socket: os.Socket,
    std_file: std.fs.File,
    stream: std.net.Stream,
    display: []const u8,

    pub const DetectError = error{MalformedWaylandSocket};
    pub fn detect() !ConnectInfo {
        if (std.posix.getenv("WAYLAND_SOCKET")) |wayland_socket| {
            const socket_fd = std.fmt.parseInt(i32, wayland_socket, 10) catch
                return error.MalformedWaylandSocket;
            return ConnectInfo{ .fd = socket_fd };
        }
        const wayland_display = std.posix.getenv("WAYLAND_DISPLAY") orelse "wayland-0";
        return ConnectInfo{ .display = wayland_display };
    }
};

pub const InitError = Allocator.Error ||
    ConnectError ||
    os.Pipe.CreateError ||
    ProxyManager.GetProxyError ||
    std.Thread.SpawnError;

pub fn init(gpa: Allocator, connect_info: ConnectInfo) InitError!void {
    _gpa = gpa;
    socket = try connect(connect_info);
    proxy_manager = ProxyManager.init(gpa, socket.handle);
    display = wl.Display{
        .proxy = try proxy_manager.getNewProxy(wl.Display),
    };
    event_queue = EventQueue.init(gpa);
    cancel_pipe = try os.Pipe.create();
    event_thread = try std.Thread.spawn(.{ .allocator = gpa }, pollEvents, .{});
}

pub fn deinit() void {
    cancel_pipe.writeAll("1") catch {};
    event_queue.cancel();
    event_thread.join();
    cancel_pipe.close();
    event_queue.deinit();
    proxy_manager.deinit();
    socket.close();
}

pub fn getDisplay() wl.Display {
    return display;
}

pub fn waitNextEvent() ?wl.Event {
    return event_queue.wait();
}

pub fn getNextEvent() ?wl.Event {
    return event_queue.get();
}

const ConnectError = error{
    InvalidSocketFd,
    NoXdgRuntimeDir,
    SocketPathTooLong,
} || os.Socket.CreateError || os.Socket.ConnectUnixError;

fn connect(info: ConnectInfo) ConnectError!os.Socket {
    return switch (info) {
        .fd => |fd| try connectToSocket(fd),
        .file => |file| try connectToSocket(file.handle),
        .socket => |sock| try connectToSocket(sock.handle.handle),
        .std_file => |std_file| try connectToSocket(std_file.handle),
        .stream => |stream| try connectToSocket(stream.handle),
        .display => |disp| try connectToDisplay(disp),
    };
}

fn connectToSocket(sockfd: i32) !os.Socket {
    const sock = os.Socket{ .handle = .{ .handle = sockfd } };
    var flags = sock.handle.getFlags() catch
        return error.InvalidSocketFd;
    flags.cloexec = true;
    sock.handle.setFlags(flags) catch unreachable;
    return sock;
}

fn connectToDisplay(disp: []const u8) !os.Socket {
    const sock = try os.Socket.create(.unix, .stream, .{ .cloexec = true }, null);
    const xdg_runtime_dir = std.posix.getenv("XDG_RUNTIME_DIR") orelse
        return error.NoXdgRuntimeDir;

    if (std.fs.path.isAbsolute(disp)) {
        try sock.connectUnix(disp);
    } else {
        var buf: [108]u8 = @splat(0);
        const path = std.fmt.bufPrint(&buf, "{s}/{s}", .{ xdg_runtime_dir, disp }) catch
            return error.SocketPathTooLong;
        try sock.connectUnix(path);
    }

    return sock;
}

fn pollEvents() !void {
    var pfds = [_]os.Pollfd{ .{
        .fd = socket.handle,
        .events = .{ .in = true },
    }, .{
        .fd = cancel_pipe.getReadFile(),
        .events = .{ .in = true },
    } };

    while (true) {
        _ = try os.poll(&pfds, -1);
        for (&pfds) |*pfd| {
            if (@as(u16, @bitCast(pfd.revents)) != 0) {
                pfd.revents = .{};
                if (pfd.fd == cancel_pipe.getReadFile()) return;
                if (pfd.fd == socket.handle) try recieveEvent();
            }
        }
    }
}

fn recieveEvent() !void {
    var head: Header = undefined;
    _ = try socket.handle.read(std.mem.asBytes(&head));

    const event = try parseEvent(head);
    switch (event) {
        .display_error => |err| {
            defer err.deinit();
            std.debug.panic("wl_display_error\n\tobject_id: {d}\n\tcode: {s}\n\tmessage: {s}\n", .{
                err.object_id,
                @tagName(@as(wl.Display.Error, @enumFromInt(err.code))),
                err.message,
            });
        },
        .display_delete_id => |delete_id| try proxy_manager.deleteId(delete_id.id),
        else => try event_queue.emplace(event),
    }
}

pub fn parseEvent(header: Header) !wl.Event {
    const event0_index = proxy_manager.proxy_type_references.items[header.object];
    const tag_name = @tagName(@as(wl.EventType, @enumFromInt(event0_index + header.opcode)));
    @setEvalBranchQuota(2048);
    inline for (@typeInfo(wl.Event).@"union".fields) |field| {
        if (std.mem.eql(u8, field.name, tag_name)) {
            const union_field_info = field;
            const struct_type = union_field_info.type;
            var struct_value: struct_type = undefined;
            struct_value.self = .{ .proxy = .{
                .id = header.object,
                .gpa = _gpa,
                .event0_index = event0_index,
                .manager = &proxy_manager,
                .socket = socket.handle,
            } };

            const size = header.length - @sizeOf(Header);

            const fd_count = count: {
                comptime var count: usize = 0;
                inline for (@typeInfo(struct_type).@"struct".fields) |s_field| {
                    if (@TypeOf(s_field) == os.File) count += 1;
                }
                break :count count;
            };

            const buf = try _gpa.alloc(u8, size);
            defer _gpa.free(buf);

            var fds: [fd_count]os.File = undefined;
            if (size != 0) {
                const read = try socket.handle.recieveMessage(@TypeOf(fds), &fds, buf, 0);
                std.debug.assert(read == size);
            }

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
                    Fixed => {
                        @field(struct_value, s_field.name) = Fixed{ .data = @bitCast(std.mem.bytesToValue(i32, buf[index .. index + 4])) };
                        index += 4;
                    },
                    Array => {
                        const len = std.mem.bytesToValue(u32, buf[index .. index + 4]);
                        index += 4;
                        const rounded_len = roundup4(len);
                        @field(struct_value, s_field.name) = try _gpa.dupe(u8, buf[index .. index + len]);
                        index += rounded_len;
                    },
                    String => {
                        const len = std.mem.bytesToValue(u32, buf[index .. index + 4]);
                        index += 4;
                        const rounded_len = roundup4(len);
                        @field(struct_value, s_field.name) = try _gpa.dupeZ(u8, buf[index .. index + len - 1]);
                        index += rounded_len;
                    },
                    os.File => {
                        if (fd_count > 0) {
                            @field(struct_value, s_field.name) = fds[fd_idx];
                            fd_idx += 1;
                        }
                    },
                    else => switch (@typeInfo(s_field.type)) {
                        .@"enum" => {
                            const int_value: u32 = std.mem.bytesToValue(u32, buf[index .. index + 4]);
                            @field(struct_value, s_field.name) = @enumFromInt(int_value);
                            index += 4;
                        },
                        .@"struct" => |s| {
                            const int_value = std.mem.bytesToValue(u32, buf[index .. index + 4]);
                            index += 4;
                            if (s.layout == .@"packed") { // Bitfield
                                comptime std.debug.assert(s.backing_integer.? == u32);
                                var s_value = s_field.type{};
                                inline for (s.fields, 0..) |f, i| {
                                    if (f.type == bool)
                                        @field(s_value, f.name) = int_value & i << i == i << i;
                                }

                                @field(struct_value, s_field.name) = s_value;
                            } else { // Object
                                comptime std.debug.assert(@hasField(s_field.type, "proxy"));
                                const proxy = Proxy{
                                    .gpa = _gpa,
                                    .id = int_value,
                                    .event0_index = event0_index,
                                    .socket = socket.handle,
                                    .manager = &proxy_manager,
                                };
                                @field(struct_value, s_field.name) = s_field.type{ .proxy = proxy };
                            }
                        },
                        else => std.debug.panic("Unexpected type: {s}", .{@typeName(s_field.type)}),
                    },
                }
            }
            return @unionInit(wl.Event, union_field_info.name, struct_value);
        }
    }
    unreachable;
}

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
const Fixed = core.Fixed;
