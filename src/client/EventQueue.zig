const std = @import("std");
const Queue = std.fifo.LinearFifo(wl.Event, .{ .Static = 64 });

const wl = @import("client_protocol");

const sys_utils = @import("../common/sys_utils.zig");
const Pipe = sys_utils.Pipe;
const Poll = sys_utils.Poll;

const Self = @This();

queue: Queue,
mutex: std.Thread.Mutex,
read_pipe: Pipe,
cancel_read_pipe: Pipe,
pfds: [2]Poll.Pollfd,

pub fn init() Pipe.CreateError!Self {
    var self = Self{
        .queue = Queue.init(),
        .mutex = .{},
        .read_pipe = try Pipe.create(),
        .cancel_read_pipe = try Pipe.create(),
        .pfds = undefined,
    };

    self.pfds = .{
        Poll.Pollfd{
            .fd = self.read_pipe.getReadFd(),
            .events = .{ .in = true },
        },
        Poll.Pollfd{
            .fd = self.cancel_read_pipe.getReadFd(),
            .events = .{ .in = true },
        },
    };

    return self;
}

pub fn deinit(self: Self) void {
    self.read_pipe.close();
    self.cancel_read_pipe.close();
    self.queue.deinit();
}

pub fn push(self: *Self, event: wl.Event) !void {
    self.mutex.lock();
    defer self.mutex.unlock();
    try self.queue.writeItem(event);
    _ = try std.posix.write(self.read_pipe.getWriteFd(), "1");
}

pub fn pop(self: *Self) ?wl.Event {
    _ = Poll.poll(&self.pfds, -1) catch return null;
    for (self.pfds) |pfd| {
        if (@as(u16, @bitCast(pfd.revents)) != 0) {
            if (pfd.fd == self.cancel_read_pipe.getReadFd()) {
                var buf: [4]u8 = undefined;
                _ = std.posix.read(self.cancel_read_pipe.getReadFd(), &buf) catch return null;
                return null;
            }
            var buf: [1]u8 = undefined;
            _ = std.posix.read(self.read_pipe.getReadFd(), &buf) catch return null;
            self.mutex.lock();
            defer self.mutex.unlock();
            return self.queue.readItem();
        }
    }
    return null;
}

pub fn cancelRead(self: Self) void {
    _ = std.posix.write(self.cancel_read_pipe.getWriteFd(), "1") catch return;
}
