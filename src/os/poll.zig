pub const Pollfd = extern struct {
    fd: File,
    events: PollEvents,
    revents: PollEvents = .{},
};

pub const PollEvents = packed struct(u16) {
    in: bool = false,
    pri: bool = false,
    out: bool = false,
    rdnorm: bool = false,
    rdband: bool = false,
    wrnorm: bool = false,
    wrband: bool = false,
    _: u9 = 0,
};

pub const PollError = error{
    ResourceTemporarilyUnavailable,
    Interrupted,
    InvalidArgument,
};

pub fn poll(pollfds: []Pollfd, timeout: i32) PollError!usize {
    const ret = system.poll(@ptrCast(pollfds.ptr), @intCast(pollfds.len), timeout);
    return switch (errno(ret)) {
        .SUCCESS => ret,
        .AGAIN => error.ResourceTemporarilyUnavailable,
        .INTR => error.Interrupted,
        .INVAL => error.InvalidArgument,
        else => unreachable,
    };
}

const std = @import("std");
const system = std.os.linux;
const errno = std.posix.errno;
const File = @import("file.zig").File;
