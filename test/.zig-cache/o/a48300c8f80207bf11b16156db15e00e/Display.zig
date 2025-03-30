const std = @import("std");
const Self = @This();
const wl = @import("generated.zig");
const Object = @import("Object.zig");

const id: u32 = 1;
next_id: u32 = 2,
sockfd: std.posix.socket_t = -1,
epollfd: std.posix.fd_t = -1,
parent: Object,
objects: std.ArrayList(Object),
allocator: std.mem.Allocator,
read_buf: []u8,

pub const ErrorEvent = struct {
    object_id: u32,
    code: u32,
    message: []const u8,
};

pub const DeleteIdEvent = struct {
    id: u32,
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
    const parent = Object{ .id = id, .display = undefined, .event0_index = 0 };
    try objects.append(parent);

    return Self{
        .sockfd = sock,
        .epollfd = epoll,
        .parent = parent,
        .objects = objects,
        .allocator = allocator,
        .read_buf = try allocator.alloc(u8, 1),
    };
}

pub fn disconnect(self: Self) void {
    self.allocator.free(self.read_buf);
    self.objects.deinit();
    std.posix.close(self.epollfd);
    std.posix.close(self.sockfd);
}

pub fn sync(self: *Self) !wl.Callback {
    self.parent.display = self;
    return try Object.sendCreateRequest(
        self.parent,
        wl.Callback,
        self,
        0,
        .{Object.Arg{ .new_id = .{} }},
    );
}

pub fn getRegistry(self: *Self) !wl.Registry {
    self.parent.display = self;
    return try Object.sendCreateRequest(
        self.parent,
        wl.Registry,
        self,
        1,
        .{Object.Arg{ .new_id = .{} }},
    );
}

pub fn allocateId(self: *Self) u32 {
    defer self.next_id += 1;
    return self.next_id;
}

const MessageHeader = packed struct {
    object: u32,
    opcode: u16,
    length: u16,
};

pub fn getNextEvent(self: *Self) !?wl.Event {
    const max_events = 32;
    var events: [max_events]std.os.linux.epoll_event = undefined;
    const event_count = std.os.linux.epoll_wait(self.epollfd, &events, max_events, -1);
    for (events[0..event_count]) |ev| {
        if (ev.data.fd != self.sockfd) continue; // TODO handle internal events as necessary
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

    const ev: wl.Event = @enumFromInt(object.event0_index + event);
    std.debug.print("{s}\n", .{@tagName(ev)});

    if (object == 2 and event == 0) {
        return wl.Event{ .wl_registry_global = .{
            .name = @as(*u32, @ptrCast(@alignCast(&self.read_buf[0]))).*,
            .interface = blk: {
                const strlen: usize = @intCast(@as(*u32, @ptrCast(@alignCast(&self.read_buf[4]))).*);
                break :blk self.read_buf[8 .. strlen + 7];
            },
            .version = @as(*u32, @ptrCast(@alignCast(&self.read_buf[len - 4]))).*,
        } };
    }

    // TODO remove this
    return null;
}
