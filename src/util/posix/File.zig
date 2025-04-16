handle: Fd,

pub const Fd = i32;

const FcntlCommand = enum(u32) {
    dupfd = 0,
    getfd = 1,
    setfd = 2,
    getfl = 3,
    setfl = 4,
    setown = 8,
    getown = 9,
    setsig = 10,
    getsig = 11,
    getlk = 12,
    setlk = 13,
    setlkw = 14,
    setown_ex = 15,
    getown_ex = 16,
    getowner_uids = 17,
};

inline fn fcntl(fd: Self, cmd: FcntlCommand, arg: usize) usize {
    return system.fcntl(fd.handle, @intCast(@intFromEnum(cmd)), arg);
}

const BaseFcntlError = error{
    BadFileDescriptor,
};

pub const AccessMode = enum(u2) {
    read_only,
    write_only,
    read_write,
};

pub const Access = packed struct(u3) {
    read: bool = false,
    write: bool = false,
    execute: bool = false,
};

pub const Type = enum(u4) {
    none = 0b0000,
    fifo = 0b0001,
    character_device = 0b0010,
    directory = 0b0100,
    block_device = 0b0110,
    regular = 0b1000,
    link = 0b1010,
    socket = 0b1100,
};

pub const Mode = packed struct(u32) {
    other_access: Access = .{},
    group_access: Access = .{},
    owner_access: Access = .{},
    sticky: bool = false,
    set_gid: bool = false,
    set_uid: bool = false,
    type: Type = .none,
    _: u16 = 0,
};

pub fn close(self: Self) void {
    _ = system.close(self.handle);
}

pub const DupeError = error{
    ProcessFdLimitReached,
} || BaseFcntlError;

// DUPFD
pub fn dupe(self: Self) DupeError!Self {
    const ret = self.fcntl(.dupfd, 0);
    return switch (Errno.get(ret)) {
        .success => .{ .handle = @intCast(ret) },
        .bad_file_descriptor => error.BadFileDescriptor,
        .too_many_files_open => error.ProcessFdLimitReached,
        else => unreachable,
    };
}

pub const Flags = packed struct(u1) {
    cloexec: bool = false,
};

pub const GetFlagsError = BaseFcntlError;

// GETFD
pub fn getFlags(self: Self) GetFlagsError!Flags {
    const ret = self.fcntl(.getfd, 0);
    return switch (Errno.get(ret)) {
        .success => @bitCast(@as(u1, @intCast(ret))),
        .bad_file_descriptor => error.BadFileDescriptor,
        else => unreachable,
    };
}

pub const SetFlagsError = BaseFcntlError;

// SETFD
pub fn setFlags(self: Self, flags: Flags) SetFlagsError!void {
    const int_flags = @as(usize, @intCast(@as(u1, @bitCast(flags))));
    const ret = self.fcntl(.setfd, int_flags);
    return switch (Errno.get(ret)) {
        .success => {},
        .bad_file_descriptor => error.BadFileDescriptor,
        else => unreachable,
    };
}

pub const GetStatusError = BaseFcntlError;

// GETFL
pub fn getStatus() GetStatusError!void {}

pub const SetStatusError = BaseFcntlError;

// SETFL
pub fn setStatus() SetStatusError!void {}

// GETLK
// SETLK
// SETLKW (advisory lock)
// SETOWN
// GETOWN
// SETSIG
// GETSIG
// SETOWN_EX
// GETOWN_EX
// GETOWNER_UIDS

pub const Lock = extern struct {
    type: Lock.Type,

    pub const Type = enum(u2) {
        read = 0,
        write = 1,
        unlock = 2,
    };
};

pub fn setLock(self: Self, lock_type: Lock.Type) !void {
    _ = self;
    _ = lock_type;
}

pub fn getLock(self: Self) !Lock {
    _ = self;
}

pub fn setAdvisoryLock(self: Self, lock_type: Lock.Type) !void {
    _ = self;
    _ = lock_type;
}

pub fn getAdvisoryLock(self: Self) !Lock {
    _ = self;
}

pub fn stdFile(self: Self) std.fs.File {
    return std.fs.File{ .handle = self.handle };
}

const Self = @This();
const std = @import("std");
const linux = std.os.linux;
const system = linux;
const io = @import("../io.zig");
const errno = @import("errno.zig");
const Errno = errno.Errno;
