queue: Queue,
mutex: std.Thread.Mutex,
read_pipe: Pipe,
cancel_read_pipe: Pipe,
pfds: [2]posix.Pollfd,

pub const CreateError = Pipe.CreateError;

pub fn init() Pipe.CreateError!Self {
    var self = Self{
        .queue = Queue.init(),
        .mutex = .{},
        .read_pipe = try Pipe.create(),
        .cancel_read_pipe = try Pipe.create(),
        .pfds = undefined,
    };

    self.pfds = .{
        posix.Pollfd{
            .fd = self.read_pipe.getReadFile(),
            .events = .{ .in = true },
        },
        posix.Pollfd{
            .fd = self.cancel_read_pipe.getReadFile(),
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
    try self.read_pipe.writeAll("1");
}

pub fn pop(self: *Self) ?wl.Event {
    _ = posix.poll(&self.pfds, -1) catch return null;
    for (self.pfds) |pfd| {
        if (@as(u16, @bitCast(pfd.revents)) != 0) {
            if (pfd.fd == self.cancel_read_pipe.getReadFile()) {
                var buf: [4]u8 = undefined;
                _ = self.cancel_read_pipe.read(&buf) catch {};
                return null;
            }
            var buf: [1]u8 = undefined;
            _ = self.read_pipe.read(&buf) catch return null;
            self.mutex.lock();
            defer self.mutex.unlock();
            return self.queue.readItem();
        }
    }
    return null;
}

pub fn cancelRead(self: Self) void {
    self.cancel_read_pipe.writeAll("1") catch {};
}

const Self = @This();
const std = @import("std");
const Queue = std.fifo.LinearFifo(wl.Event, .{ .Static = 64 });
const wl = @import("client_protocol");
const util = @import("util");
const posix = util.posix;
const Pipe = posix.Pipe;
