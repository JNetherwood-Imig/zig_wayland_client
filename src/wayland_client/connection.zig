var alloc: Allocator = undefined;
var socket: os.Socket = undefined;
var event_queue: EventQueue = undefined;
var cancel_pipe: os.Pipe = undefined;
var event_thread: std.Thread = undefined;
var display: wl.Display = undefined;
var read_buf = [_]u8{0} ** 65535;
var write_buf = [_]u8{0} ** 65535;

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
    std.Thread.SpawnError;

pub fn init(gpa: Allocator, connect_info: ConnectInfo) InitError!void {
    alloc = gpa;
    socket = try connect(connect_info);
    try pm.init(gpa, socket);
    display = wl.Display{
        .proxy = .{ .id = 1, .event0_index = 0 },
    };
    event_queue = EventQueue.init(gpa);
    cancel_pipe = try os.Pipe.create();
    event_thread = try std.Thread.spawn(.{ .allocator = gpa }, pollEvents, .{});
}

pub const InitAutoError = InitError || ConnectInfo.DetectError;

pub fn initAuto(gpa: Allocator) InitAutoError!void {
    try init(gpa, try ConnectInfo.detect());
}

pub fn deinit() void {
    cancel_pipe.writeAll("1") catch {};
    event_queue.cancel();
    event_thread.join();
    cancel_pipe.close();
    event_queue.deinit();
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

    const event = try deserializer.parseEvent(head);
    switch (event) {
        .display_error => |err| {
            defer err.deinit();
            std.debug.panic("wl_display_error\n\tobject_id: {d}\n\tcode: {s}\n\tmessage: {s}\n", .{
                err.object_id,
                @tagName(@as(wl.Display.Error, @enumFromInt(err.code))),
                err.message,
            });
        },
        .display_delete_id => |delete_id| try pm.deleteId(delete_id.id),
        else => try event_queue.emplace(event),
    }
}

fn getEventType(ev_idx: usize) std.builtin.Type.UnionField {
    std.math.pow(comptime_int, 2, 16) - 1;
    const info = @typeInfo(wl.Event).@"union";
    return info.fields[ev_idx];
}

fn countFds(comptime T: type) usize {
    comptime var count: usize = 0;
    inline for (@typeInfo(T).@"struct".fields) |s_field| {
        if (@TypeOf(s_field) == os.File) count += 1;
    }
    return count;
}

pub fn parseEvent(head: Header, buf: []const u8) wl.Event {
    const struct_info = getEventType(pm.type_references[head.object] + head.opcode);
    const fd_count = countFds(struct_info.type);
    var fds: [fd_count]
    return @unionInit(wl.Event, struct_info.name, deserialize(struct_info.type, buf, &fds));
}

fn deserialize(comptime T: type, buf: []const u8, fds: []const File) T {
    var parsed: T = undefined;
}

fn readUint(self: Self) u32 {
    defer self.buf = self.buf[4..];
    return std.mem.bytesToValue(u32, self.buf[0..4]);
}

fn readInt(self: Self) i32 {
    defer self.buf = self.buf[4..];
    return std.mem.bytesToValue(i32, self.buf[0..4]);
}

fn readFixed(self: Self) Fixed {
    return Fixed{
        .data = self.readInt(),
    };
}

fn readString(self: Self) String {
    const len = self.readUint();
    const padded_len = roundup4(len);
    defer self.buf = self.buf[padded_len..];
    return self.buf[0..len - 1];
}

fn readArray(self: Self) Array {
    const len = self.readUint();
    const padded_len = roundup4(len);
    defer self.buf = self.buf[padded_len..];
    return self.buf[0..len];
}

fn readObject(self: Self, comptime Interface: type) Interface {}

fn readNullableObject(self: Self, comptime Interface: type) ?Interface {}

fn readFd(self: Self) File {}

pub fn readAll(self: Self, header: Header) wl.Event {
    var struct_value: StructType = undefined;
    struct_value.self = .{ .proxy = .{
        .id = header.object,
        .event0_index = event0_index,
    } };

    var len = try pm.socket.recieveMessage(@TypeOf(fds), &self.fds, &self.buf, 0);
    while (len < header.length) {
        std.log.warn("Incomplete read", .{});
        len += try pm.socket.read(buf[len..]);
    }

    inline for (@typeInfo(struct_type).@"struct".fields) |field| {
        if (comptime std.mem.eql(u8, s_field.name, "self")) continue;
        @field(struct_value, field.name) = switch (field.type) {
            u32 => self.readUint(),
            i32 => self.readInt(),
            Fixed => self.readFixed(),
            Array => self.readArray(),
            String => self.readString(),
            File => {
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
}

const std = @import("std");
const wl = @import("wayland_client_protocol");
const os = @import("os");
const shared = @import("shared");
const s = shared.serializer_utils;
const testing = std.testing;
const roundup4 = s.roundup4;
const pm = shared.proxy_manager;
const Proxy = core.Proxy;
const EventQueue = @import("EventQueue.zig");
const Allocator = std.mem.Allocator;
const Header = s.Header;
const Array = s.Array;
const String = s.String;
const Fixed = shared.Fixed;
