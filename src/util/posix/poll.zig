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

pub fn poll(pollfds: []Pollfd, timeout: i32) !usize {
    const ret = system.poll(@ptrCast(pollfds.ptr), @intCast(pollfds.len), timeout);
    return switch (Errno.get(ret)) {
        .success => ret,
        .resource_temporarily_unavailable => error.ResourceTemporarilyUnavailable,
        .interrupted_system_call => error.Interrupted,
        .invalid_argument => error.InvalidArgument,
        else => unreachable,
    };
}

const std = @import("std");
const system = std.os.linux;
const File = @import("file.zig").File;
const Errno = @import("errno.zig").Errno;
