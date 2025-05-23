const std = @import("std");
const wl = @import("protocol");
const shared = @import("shared");
const EventQueue = @import("EventQueue.zig");
const Deserializer = @import("Deserializer.zig");
const Socket = shared.Socket;
const ProxyManager = shared.ProxyManager;
const Proxy = shared.Proxy;
const Allocator = std.mem.Allocator;
const Fd = std.posix.fd_t;

const DisplayConnection = @This();

gpa: Allocator,
socket: Socket,
proxy_manager: ProxyManager,
event_queue: EventQueue,
cancel_pipe: [2]Fd,
event_thread: std.Thread,
proxy: wl.Display,

threadlocal var read_buf: [std.math.maxInt(u16) + 8]u8 = undefined;
threadlocal var write_buf: [std.math.maxInt(u16) + 8]u8 = undefined;

pub const ConnectInfo = union(enum) {
    fd: Fd,
    display: [:0]const u8,

    pub const GetError = error{MalformedWaylandSocket};

    pub fn get() GetError!ConnectInfo {
        if (std.posix.getenv("WAYLAND_SOCKET")) |wayland_socket| {
            const socket = std.fmt.parseInt(i32, wayland_socket, 10) catch
                return error.MalformedWaylandSocket;
            return ConnectInfo{ .socket = socket };
        }
        const wayland_display = std.posix.getenv("WAYLAND_DISPLAY") orelse "wayland-0";
        return ConnectInfo{ .display = wayland_display };
    }
};

pub const InitError = Allocator.Error ||
    Socket.InitFdError ||
    Socket.InitDisplayError ||
    std.posix.PipeError ||
    std.Thread.SpawnError;

pub fn init(gpa: Allocator, connect_info: ConnectInfo) InitError!*DisplayConnection {
    const self = try gpa.create(DisplayConnection);
    errdefer gpa.destroy(self);

    self.gpa = gpa;
    self.socket = switch (connect_info) {
        .fd => |fd| try Socket.initFd(fd),
        .display => |display| try Socket.initDisplay(display),
    };
    self.proxy_manager = ProxyManager.init(gpa, self.socket.handle);
    self.proxy = wl.Display{
        .proxy = Proxy{
            .gpa = gpa,
            .id = 1,
            .event0_index = 0,
            .socket = null,
            .manager = &self.proxy_manager,
        },
    };
    self.event_queue = EventQueue.init(gpa);
    self.cancel_pipe = try std.posix.pipe();
    self.event_thread = try std.Thread.spawn(.{ .allocator = self.gpa }, pollEvents, .{self});

    return self;
}

pub fn initAuto(gpa: Allocator) (ConnectInfo.GetError || InitError)!*DisplayConnection {
    return init(gpa, try ConnectInfo.get());
}

pub fn deinit(self: *DisplayConnection) void {
    std.posix.write(self.cancel_pipe[1], "1") catch {};
    self.event_queue.cancel();
    self.event_thread.join();
    std.posix.close(self.cancel_pipe[0]);
    std.posix.close(self.cancel_pipe[1]);
    self.event_queue.deinit();
    self.proxy_manager.deinit();
    self.socket.close();
    self.gpa.destroy(self);
}

// TODO make this return a wl.DisplayError error set
pub fn waitNextEvent(self: *DisplayConnection) ?wl.Event {
    return self.event_queue.wait();
}

// TODO make this return a wl.DisplayError error set
pub fn getNextEvent(self: *DisplayConnection) ?wl.Event {
    return self.event_queue.get();
}

fn pollEvents(self: *DisplayConnection) !void {
    var pfds = [_]std.posix.pollfd{
        std.posix.pollfd{
            .fd = self.socket.handle,
            .events = std.posix.POLL.IN,
            .revents = 0,
        },
        std.posix.pollfd{
            .fd = self.cancel_pipe[0],
            .events = std.posix.POLL.IN,
            .revents = 0,
        },
    };

    while (true) {
        _ = try std.posix.poll(&pfds, -1);
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
    const event = Deserializer.parseEvent(self.socket, &read_buf, &self.proxy_manager);
    switch (event) {
        // FIXME This error handling approach does not work
        // Errors need to be collected into one enum (and ideally error set)
        // Alternatively errors should maybe be structs instead and store their descriptions as string literals for logging
        // A lookup table of error enum indices needs to be kept similarly to the ProxyManager.proxy_type_references
        // The actual error can then be derived from the object id and error code
        // Once the error is derived, the associated error message can be logged to err using std.log
        // and the appropriate error set member can be returned from DisplayConnection.getNextEvent or waitNextEvent
        .display_error => |err| {
            defer err.deinit();
            std.debug.panic("wl_display_error\n\tobject_id: {d}\n\tcode: {s}\n\tmessage: {s}\n", .{
                err.object_id,
                @tagName(@as(wl.Display.Error, @enumFromInt(err.code))),
                err.message,
            });
        },
        .display_delete_id => |delete_id| try self.proxy_manager.deleteId(delete_id.id),
        else => try self.event_queue.emplace(event),
    }
}
