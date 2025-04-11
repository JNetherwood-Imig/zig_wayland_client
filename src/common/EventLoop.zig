const std = @import("std");
const Thread = std.Thread;
const PollfdList = std.ArrayList(Poll.Pollfd);
const SourceList = std.ArrayList(EventSource);
const Allocator = std.mem.Allocator;

const sys_utils = @import("sys_utils.zig");
const Fd = sys_utils.Fd;
const Pipe = sys_utils.Pipe;
const Signalfd = sys_utils.Signalfd;
const Poll = sys_utils.Poll;
const Sig = sys_utils.Sig;

const wl = @import("generated");

const Self = @This();

allocator: Allocator,
poll_cancel: Pipe,
pollfd_list: PollfdList,
poll_thread: Thread,
sources: SourceList,

pub const Error = Allocator.Error || Pipe.CreateError;

pub fn init(allocator: Allocator) Error!Self {
    return Self{
        .allocator = allocator,
        .pollfd_list = PollfdList.init(allocator),
        .poll_cancel = try Pipe.create(),
        .poll_thread = undefined,
        .sources = SourceList.init(allocator),
    };
}

pub fn deinit(self: *Self) void {
    self.terminate();
    self.poll_thread.join();
    for (self.sources.items) |source| source.deinit();
    self.sources.deinit();
    self.pollfd_list.deinit();
    self.poll_cancel.close();
}

pub const StartError = Thread.SpawnError || Allocator.Error;

pub fn start(self: *Self) StartError!void {
    try self.pollfd_list.append(
        Poll.Pollfd{
            .fd = self.poll_cancel.getReadFd(),
            .events = .{ .in = true },
        },
    );
    self.poll_thread = try Thread.spawn(
        .{ .allocator = self.allocator },
        pollEvents,
        .{self},
    );
}

pub fn terminate(self: Self) void {
    _ = std.posix.write(self.poll_cancel.getWriteFd(), "1") catch return;
}

pub const EventMask = packed struct(u2) {
    readable: bool = false,
    writable: bool = false,
};

pub const EventFdSourceCallback = *const fn (
    EventMask,
    ?*anyopaque,
) anyerror!void;

pub const EventSignalSourceCallback = *const fn (
    Sig,
    ?*anyopaque,
) anyerror!void;

pub const EventSource = union(enum) {
    fd: struct {
        callback: EventFdSourceCallback,
        fd: Fd,
        data: ?*anyopaque,
        pub fn deinit(self: @This()) void {
            _ = self;
        }
    },

    signal: struct {
        callback: EventSignalSourceCallback,
        sigfd: Signalfd,
        data: ?*anyopaque,
        pub fn deinit(self: @This()) void {
            self.sigfd.close();
        }
    },

    pub fn deinit(self: EventSource) void {
        switch (self) {
            .fd => |fd| fd.deinit(),
            .signal => |sig| sig.deinit(),
        }
    }
};

pub const AddFdError = Thread.SpawnError || Allocator.Error;

pub fn addFd(
    self: *Self,
    fd: Fd,
    events: EventMask,
    callback: EventFdSourceCallback,
    data: ?*anyopaque,
) !void {
    const pfd = Poll.Pollfd{ .fd = fd, .events = .{
        .in = events.readable,
        .out = events.writable,
    } };
    self.cancelPoll();
    self.poll_thread.join();
    try self.pollfd_list.append(pfd);
    self.poll_thread = try Thread.spawn(
        .{ .allocator = self.allocator },
        pollEvents,
        .{self},
    );
    try self.sources.append(.{ .fd = .{
        .callback = callback,
        .fd = fd,
        .data = data,
    } });
}

pub const AddSignalsError = Signalfd.CreateError || Allocator.Error;

pub fn addSignals(
    self: *Self,
    signals: Signalfd.Signals,
    callback: EventSignalSourceCallback,
    data: ?*anyopaque,
) !void {
    self.cancelPoll();
    self.poll_thread.join();
    const sigfd = try Signalfd.create(signals);
    const pfd = Poll.Pollfd{
        .fd = sigfd.handle,
        .events = .{ .in = true },
    };
    try self.pollfd_list.append(pfd);
    try self.sources.append(.{ .signal = .{
        .callback = callback,
        .sigfd = sigfd,
        .data = data,
    } });
    self.poll_thread = try Thread.spawn(
        .{ .allocator = self.allocator },
        pollEvents,
        .{self},
    );
}

fn pollEvents(self: *Self) !void {
    while (true) {
        _ = try Poll.poll(self.pollfd_list.items, -1);
        for (self.pollfd_list.items) |*pfd| {
            if (@as(u16, @bitCast(pfd.revents)) != 0) {
                if (pfd.fd == self.poll_cancel.getReadFd()) {
                    var buf: [4]u8 = undefined;
                    _ = try std.posix.read(self.poll_cancel.getReadFd(), &buf);
                    return;
                }

                const source: EventSource = for (self.sources.items) |source|
                    switch (source) {
                        .fd => |fd| if (fd.fd == pfd.fd)
                            break source,
                        .signal => |sig| if (sig.sigfd.handle == pfd.fd)
                            break source,
                    }
                else
                    unreachable;

                switch (source) {
                    .fd => |fd| {
                        const event_mask = EventMask{
                            .readable = pfd.revents.in,
                            .writable = pfd.revents.out,
                        };
                        try fd.callback(event_mask, fd.data);
                    },
                    .signal => |sig| {
                        const info = try sig.sigfd.read();
                        try sig.callback(@enumFromInt(info.signo), sig.data);
                    },
                }
                pfd.revents = .{};
            }
        }
    }
}

fn cancelPoll(self: *Self) void {
    _ = std.posix.write(self.poll_cancel.getWriteFd(), "1") catch return;
}
