handle: File,

pub const CreateFlags = packed struct(u1) {
    cloexec: bool = false,
};

pub const CreateError = error{
    InvalidFlags,
    ProcessFdLimitReached,
    SystemFdLimitReached,
    OutOfMemory,
};

pub fn create(flags: CreateFlags) CreateError!Self {
    const ret = system.epoll_create1(@intCast(@as(
        @typeInfo(CreateFlags).@"struct".backing_integer.?,
        @bitCast(flags),
    )));
    return switch (Errno.get(ret)) {
        .success => .{ .handle = .{ .handle = @intCast(ret) } },
        .invalid_argument => error.InvalidFlags,
        .too_many_open_files => error.ProcessFdLimitReached,
        .too_many_open_files_in_system => error.SystemFdLimitReached,
        .cannot_allocate_memory => error.OutOfMemory,
        else => unreachable,
    };
}

pub fn close(self: Self) void {
    self.handle.close();
}

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
    fd: File,
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

pub const AddError = error{
    BadFileDescriptor,
    FdAlreadyAdded,
    InvalidArgument,
    EpollMonitorLoop,
    OutOfMemory,
    FdWatchLimitReached,
    EpollNotSupportedForFd,
};

pub fn add(self: Self, fd: File, event: Event) AddError!void {
    const ret = self.ctl(.add, fd, event);
    return switch (Errno.get(ret)) {
        .success => {},
        .bad_file_descriptor => error.BadFileDescriptor,
        .file_exists => error.FdAlreadyAdded,
        .invalid_argument => error.InvalidArgument,
        .too_many_levels_of_symbolic_links => error.EpollMonitorLoop,
        .cannot_allocate_memory => error.OutOfMemory,
        .no_space_left_on_device => error.FdWatchLimitReached,
        .operation_not_permitted => error.EpollNotSupportedForFd,
        else => unreachable,
    };
}

pub const ModError = error{
    BadFileDescriptor,
    InvalidArgument,
    FdNotRegistered,
    OutOfMemory,
    EpollNotSupportedForFd,
};

pub fn mod(self: Self, fd: File, event: Event) ModError!void {
    const ret = self.ctl(.mod, fd, event);
    return switch (Errno.get(ret)) {
        .success => {},
        .bad_file_descriptor => error.BadFileDescriptor,
        .invalid_argument => error.InvalidArgument,
        .no_such_file_or_directory => error.FdNotRegistered,
        .cannot_allocate_memory => error.OutOfMemory,
        .operation_not_permitted => error.EpollNotSupportedForFd,
        else => unreachable,
    };
}

pub const DelError = error{
    BadFileDescriptor,
    InvalidArgument,
    FdNotRegistered,
    OutOfMemory,
    EpollNotSupportedForFd,
};

pub fn del(self: Self, fd: File) DelError!void {
    const ret = self.ctl(.del, fd, null);
    return switch (Errno.get(ret)) {
        .success => {},
        .bad_file_descriptor => error.BadFileDescriptor,
        .invalid_argument => error.InvalidArgument,
        .no_such_file_or_directory => error.FdNotRegistered,
        .cannot_allocate_memory => error.OutOfMemory,
        .operation_not_permitted => error.EpollNotSupportedForFd,
        else => unreachable,
    };
}

fn ctl(
    self: Self,
    op: enum(u32) { add = 1, del, mod },
    fd: File,
    event: ?Event,
) usize {
    return system.epoll_ctl(
        self.handle.handle,
        @intFromEnum(op),
        fd.handle,
        @ptrCast(@constCast(&event)),
    );
}

pub const WaitError = error{
    BadAddress,
    InterruptedSystemCall,
    BadFileDescriptor,
    InvalidArgument,
};
pub fn wait(
    self: Self,
    events: []Event,
    timeout: i32,
) WaitError!usize {
    const ret = system.epoll_wait(
        self.handle.handle,
        @ptrCast(events.ptr),
        @intCast(events.len),
        timeout,
    );
    return switch (Errno.get(ret)) {
        .success => ret,
        .bad_address => error.BadAddress,
        .interrupted_system_call => error.InterruptedSystemCall,
        .bad_file_descriptor => error.BadFileDescriptor,
        .invalid_argument => error.InvalidArgument,
        else => unreachable,
    };
}

const Self = @This();
const std = @import("std");
const system = std.os.linux;
const File = @import("file.zig").File;
const Errno = @import("errno.zig").Errno;
const io = @import("../io.zig");
