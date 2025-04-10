const std = @import("std");
const Self = @This();
const wl = @import("generated.zig");
const Object = @import("Object.zig");
const IdAllocator = @import("IdAllocator.zig");

next_id: u32 = 2,
sockfd: std.posix.socket_t = -1,
epollfd: std.posix.fd_t = -1,
proxy: Object,
objects: std.ArrayList(Object),
allocator: std.mem.Allocator,
read_buf: []u8,
globals: std.ArrayList(Global),

const Connection = struct {
    const Socket = struct {
        socket: std.posix.socket_t,
        display: ?[]const u8,
        pub fn init() error{
            InvalidWaylandSocket,
            NoXdgRuntimeDir,
            PathConcatFailed,
        }!SocketInfo {
            const wayland_socket = std.posix.getenv("WAYLAND_SOCKET");
            if (wayland_socket) |sock| {
                const sockfd = std.fmt.parseInt(std.posix.socket_t, sock, 10) catch return error.InvalidWaylandSocket;
                var flags = std.os.linux.fcntl(sockfd, std.posix.F.GETFD, 0);
                const err = std.posix.errno(flags);
                if (err == .BADF) return error.InvalidWaylandSocket;
                flags |= std.posix.FD_CLOEXEC;
                std.posix.fcntl(sockfd, std.posix.F.SETFD, flags) catch return error.InvalidWaylandSocket;
                return .{ .socket = sockfd };
            }

            var display_buf: [108]u8 = undefined;
            const wayland_display = std.posix.getenv("WAYLAND_DISPLAY") orelse "wayland-0";
            if (std.fs.path.isAbsolute(wayland_display)) {
                @memcpy(&display_buf, wayland_display);
            } else {
                const xdg_runtime_dir = std.posix.getenv("XDG_RUNTIME_DIR") orelse return error.NoXdgRuntimeDir;
                std.fmt.bufPrint(
                    &display_buf,
                    "{s}/{s}",
                    .{ xdg_runtime_dir, wayland_display },
                ) catch return error.PathConcatFailed;
            }
            return .{ .display = display_buf };
        }
    };
    allocator: std.mem.Allocator,
    id_allocator: IdAllocator,
    sock: std.posix.socket_t,
    epoll: std.posix.socket_t,
    display: wl.Display,
    globals: std.ArrayList(Global),
    objects: std.ArrayList(Object),

    pub fn init(allocator: std.mem.Allocator, socket_info: SocketInfo) error{}!Connection {}

    pub fn deinit(self: Connection) void {}
};

const Global = struct {
    name: u32,
    interface: []const u8,
    version: u32,
};

pub fn connect(allocator: std.mem.Allocator) !Self {
    const sock: std.posix.socket_t = init: {
        const wayland_sock = std.posix.getenv("WAYLAND_SOCK");
        if (wayland_sock) |s| {
            const fd = try std.fmt.parseInt(std.posix.socket_t, s, 10);
            const flags = try std.posix.fcntl(fd, std.posix.F.GETFD, 0);
            _ = try std.posix.fcntl(fd, std.posix.F.SETFD, flags | std.posix.FD_CLOEXEC);
            break :init fd;
        }
        const runtime_dir = std.posix.getenv("XDG_RUNTIME_DIR") orelse return error.NoXdgRuntimeDir;
        const wayland_display = std.posix.getenv("WAYLAND_DISPLAY") orelse "wayland-0";

        var addr = std.posix.sockaddr.un{ .path = .{0} ** 108 };
        const fd = try std.posix.socket(
            std.posix.AF.UNIX,
            std.posix.SOCK.STREAM | std.posix.SOCK.NONBLOCK,
            0,
        );
        errdefer std.posix.close(fd);

        if (std.fs.path.isAbsolute(wayland_display)) {
            @memcpy(&addr.path, wayland_display);
        } else {
            var buf: [108]u8 = undefined;
            @memcpy(
                addr.path[0 .. runtime_dir.len + 1 + wayland_display.len],
                try std.fmt.bufPrint(&buf, "{s}/{s}", .{ runtime_dir, wayland_display }),
            );
        }

        try std.posix.connect(fd, @ptrCast(&addr), @sizeOf(@TypeOf(addr)));
        break :init fd;
    };

    errdefer std.posix.close(sock);

    const epoll = try std.posix.epoll_create1(0);

    var ev = std.os.linux.epoll_event{ .events = std.os.linux.EPOLL.IN, .data = .{ .fd = sock } };

    try std.posix.epoll_ctl(epoll, std.os.linux.EPOLL.CTL_ADD, sock, &ev);

    var objects = std.ArrayList(Object).init(allocator);
    const proxy = Object{ .id = id, .display = undefined };
    try objects.append(proxy);

    return Self{
        .sockfd = sock,
        .epollfd = epoll,
        .proxy = proxy,
        .objects = objects,
        .allocator = allocator,
        .read_buf = try allocator.alloc(u8, 1),
        .globals = std.ArrayList(Global).init(allocator),
    };
}

pub fn disconnect(self: Self) void {
    self.globals.deinit();
    self.allocator.free(self.read_buf);
    self.objects.deinit();
    std.posix.close(self.epollfd);
    std.posix.close(self.sockfd);
}

pub fn allocateId(self: *Self) u32 {
    defer self.next_id += 1;
    return self.next_id;
}
pub fn waitNextEvent(self: *Self) !?wl.Event {
    while (try nextEvent(self, -1)) |ev| switch (ev) {
        .display_error => |err| {
            _ = err;
        },
        .display_delete_id => |del_id| {
            _ = del_id;
        },
        .registry_global => |glob| {
            _ = glob;
        },
        .registry_global_remove => |glob| {
            _ = glob;
        },
        .callback_done => |data| {
            _ = data;
        },
        else => return ev,
    };
    return null;
}

fn nextEvent(self: *Self, timeout: i32) !?wl.Event {
    const max_events = 32;
    var events: [max_events]std.os.linux.epoll_event = undefined;
    const event_count = std.os.linux.epoll_wait(self.epollfd, &events, max_events, timeout);
    for (events[0..event_count]) |ev| {
        if (ev.data.fd != self.sockfd) continue;
        return try nextSockEvent(self);
    }
    return null;
}

fn nextSockEvent(self: *Self) !?wl.Event {
    var head: MessageHeader = undefined;
    const read = try std.posix.read(self.sockfd, @as([*]u8, @ptrCast(@alignCast(&head)))[0..8]);

    if (read == 0) return null;

    const object_id: u32 = head.object;
    const event: u32 = @intCast(head.opcode);
    const len: usize = @intCast(head.length - 8);
    self.allocator.free(self.read_buf);
    self.read_buf = try self.allocator.alloc(u8, len);

    _ = try std.posix.read(self.sockfd, self.read_buf);

    const object: Object = for (self.objects.items) |obj| {
        if (obj.id == object_id) break obj;
    } else unreachable;

    const ev_idx = object.event0_index + event;

    return inline for (@typeInfo(wl.EventType).@"enum".fields) |field| {
        if (field.value == ev_idx) {
            var val: @TypeOf(@field(@unionInit(wl.Event, field.name, undefined), field.name)) = undefined;
            var ptr: [*]u8 = self.read_buf.ptr;

            @field(val, "self") = @fieldParentPtr("proxy", &object);

            inline for (@typeInfo(@TypeOf(val)).@"struct".fields) |f| {
                switch (@typeInfo(f.type)) {
                    .int => |i| {
                        @field(val, f.name) = @as(if (i.signedness == .signed) *i32 else *u32, @ptrCast(@alignCast(ptr))).*;
                        ptr += 4;
                    },
                    .pointer => |p| {
                        if (p.is_const) continue;
                        var slice_len: usize = @intCast(@as(*u32, @ptrCast(@alignCast(ptr))).*);
                        ptr += 4;
                        if (p.size == .slice) slice_len -= 1;
                        @field(val, f.name) = @ptrCast(ptr[0..slice_len]);
                        ptr += (slice_len + 3) & ~@as(u32, 3);
                    },
                    else => unreachable,
                }
            }
            break @unionInit(wl.Event, field.name, val);
        }
    } else unreachable;
}
