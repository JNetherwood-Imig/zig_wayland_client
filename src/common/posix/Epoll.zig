handle: File,

pub const CreateError = error{};
pub inline fn create(flags: u32) CreateError!Self {
    return .{ .handle = try system.epoll_create1(flags) };
}

pub fn close(self: Self) void {
    self.handle.close();
}

pub const Ctl = enum(u2) {
    add = 1,
    del = 2,
    mod = 3,
};

pub const Events = packed struct(u16) {
    in: bool = false,
    pri: bool = false,
    out: bool = false,
    err: bool = false,
    hup: bool = false,
    rdnorm: bool = false,
    wrnorm: bool = false,
    rdband: bool = false,
    wrband: bool = false,
    msg: bool = false,
    _: u6 = 0,
};

pub const Data = extern union {
    ptr: usize,
    fd: i32,
    u32: u32,
    u64: u64,
};

pub const Event = extern struct {
    events: Events,
    data: Data align(switch (@import("builtin").cpu.arch) {
        .x86_64 => 4,
        else => @alignOf(Data),
    }),
};

pub const CtlError = error{
    BadFileDescriptor,
    FdAlreadyAdded,
    InvalidArguments,
    EpollMonitorLoop,
    FdNotRegistered,
    SystemResources,
    OutOfSpace,
    EpollNotSupportedForFd,
};

pub fn ctl(
    self: Self,
    op: Ctl,
    fd: Fd,
    event: Event,
) CtlError!void {
    var ev = event;
    const ret = system.epoll_ctl(
        self.handle,
        @intFromEnum(op),
        fd,
        @ptrCast(&ev),
    );
    return switch (Errno.get(ret)) {
        .success => {},
        else => unreachable,
    };
}

pub const WaitError = error{
    BadAddress,
    InterruptedSystemCall,
    BadFileDescriptor,
    InvalidArguments,
};
pub fn wait(
    self: Self,
    events: []Event,
    timeout: i32,
) WaitError!usize {
    const ret = system.epoll_wait(
        self.handle,
        @ptrCast(events.ptr),
        @intCast(events.len),
        timeout,
    );
    return switch (Errno.get(ret)) {
        .success => ret,
        .bad_address => error.BadAddress,
        .interrupted_system_call => error.InterruptedSystemCall,
        .bad_file_descriptor => error.BadFileDescriptor,
        .invalid_arguments => error.InvalidArguments,
        else => unreachable,
    };
}

const Self = @This();
const std = @import("std");
const system = std.os.linux;
const File = @import("File.zig");
const Fd = File.Fd;
const Errno = @import("errno.zig").Errno;
const io = @import("../io.zig");
