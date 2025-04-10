const std = @import("std");
const wl = @import("generated");
const sys_utils = @import("sys_utils.zig");
const Epoll = sys_utils.Epoll;
const Pipe = sys_utils.Pipe;
const Signalfd = sys_utils.Signalfd;
const Self = @This();

// Design goals:
// deinit function for each event, and wl.Event as a whole which the caller should use
// event reading and parsing is done on a separate thread
// pools/arenas are not to be considered as very few events will require a heap allocation
// queue lives on stack
// std.Thread.Mutex
// event handler holds queue, epoll, signalfds, server fd
// event loop should probably have a generic event interface like wl_event_loop
// support: signal, fd, timer?

const Queue = std.fifo.LinearFifo(wl.Event, .{ .Static = 64 });

pub const Error = error{} || Epoll.CreateError || Pipe.CreateError;

epoll: Epoll,
queue: Queue,
thread: std.Thread,
mutex: std.Thread.Mutex,
quit_pipe: Pipe,
display_fd: std.net.Stream,
signalfd: Signalfd,

pub fn init(display_fd: std.net.Stream) !Self {
    return Self{
        .epoll = try Epoll.create(0),
        .queue = Queue.init(),
        .thread = .{},
        .mutex = .{},
        .quit_pipe = try Pipe.create(),
        .display_fd = display_fd,
        .signalfd = try Signalfd.create(.{
            .interrupt = true,
            .terminated = true,
            .quit = true,
            .kill = true,
        }),
    };
}

pub fn deinit(self: Self) void {
    try std.posix.write(self.quit_pipe.getWriteFd(), "q");
    self.thread.join();
    self.epoll.close();
    self.quit_pipe.close();
    self.queue.deinit();
}

pub fn start(self: *Self) void {
    _ = self;
}
