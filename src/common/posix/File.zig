handle: Fd,

pub const Fd = i32;

pub const FcntlCommand = enum(u32) {
    dupfd = 0,
    getfd = 1,
    setfd = 2,
    getfl = 3,
    setfl = 4,
    getlk = 5,
    setlk = 6,
    setlkw = 7,
    setown = 8,
    getown = 9,
    setsig = 10,
    getsig = 11,

    setown_ex = 15,
    getown_ex = 16,
    getowner_uids = 17,
};

pub const FcntlError = error{
    OperationNotPermitted,
    NoSuchProcess,
    InterruptedSystemCall,
    BadFileDescriptor,
    ResourceTemporarilyUnavailable,
    PermissionDenied,
    InvalidArgument,
    TooManyOpenFiles,
    ResourceDeadlockAvoided,
    NoLocksAvailable,
    ValueTooLargeForDefinedDataType,
};

fn fcntl(fd: Self, cmd: FcntlCommand, arg: usize) FcntlError!usize {
    const ret = system.fcntl(fd.handle, @intCast(@intFromEnum(cmd)), arg);
    const err = Errno.get(ret);
    return switch (err) {
        .success => ret,
        .operation_not_permitted => error.OperationNotPermitted,
        .no_such_process => error.NoSuchProcess,
        .interrupted_system_call => error.InterruptedSystemCall,
        .bad_file_descriptor => error.BadFileDescriptor,
        .resource_temporarily_unavailable => error.ResourceTemporarilyUnavailable,
        .permission_denied => error.PermissionDenied,
        .invalid_argument => error.InvalidArgument,
        .too_many_open_files => error.TooManyOpenFiles,
        .resource_deadlock_avoided => error.ResourceDeadlockAvoided,
        .no_locks_available => error.NoLocksAvailable,
        .value_too_large_for_defined_data_type => error.ValueTooLargeForDefinedDataType,
        else => unreachable,
    };
}

pub const AccessMode = enum(u2) {
    read_only,
    write_only,
    read_write,
};

pub const OpenOptions = packed struct(u32) {
    access_mode: AccessMode = .read_only,
    _2: u4 = 0,
    create: bool = false,
    exclusive: bool = false,
    no_controlling_tty: bool = false,
    truncate: bool = false,
    append: bool = false,
    nonblocking: bool = false,
    data_synchronized_io: bool = false,
    asynchronous_io: bool = false,
    direct_io: bool = false,
    _15: u1 = 0,
    ensure_directory: bool = false,
    no_follow_symlinks: bool = false,
    no_access_time: bool = false,
    close_on_exec: bool = false,
    file_synchronized: bool = false,
    path_only: bool = false,
    create_temp: bool = false,
    _: u9 = 0,
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

pub const OpenError = error{
    AccessDenied,
    AlreadyExists,
    NotFound,
    PathTooLong,
    SymLinkLoop,
    IsDirectory,
    InvalidArgument,
    FilesystemBusy,
    FilesystemFull,
    ReadOnlyFilesystem,
    TooManyOpenFiles,
    BadDescriptor,
    BadAddress,
    FileTooLarge,
    MemoryUnavailable,
    UnsupportedOperation,
    WouldBlock,
};

pub fn open(
    path: [:0]const u8,
    options: OpenOptions,
    mode: Mode,
) OpenError!Self {
    while (true) {
        const ret = system.open(path, @bitCast(options), @intCast(@as(u32, @bitCast(mode))));
        const err = Errno.get(ret);
        switch (err) {
            .success => return .{ .handle = @intCast(ret) },

            .interrupted_system_call => continue,
            .permission_denied, .operation_not_permitted => return error.AccessDenied,
            .file_exists => return error.AlreadyExists,
            .no_such_file_or_directory, .no_such_device, .no_such_device_or_address => return error.NotFound,
            .file_name_too_long => return error.PathTooLong,
            .too_many_levels_of_symbolic_links => return error.SymLinkLoop,
            .is_a_directory => return error.IsDirectory,
            .invalid_argument, .value_too_large_for_defined_data_type => return error.InvalidArgument,
            .device_or_resource_busy, .text_file_busy => return error.FilesystemBusy,
            .no_space_left_on_device, .disk_quota_exceeded => return error.FilesystemFull,
            .read_only_file_system => return error.ReadOnlyFilesystem,
            .too_many_open_files, .too_many_open_files_in_system => return error.TooManyOpenFiles,
            .bad_file_descriptor => return error.BadDescriptor,
            .bad_address => return error.BadAddress,
            .file_too_large => return error.FileTooLarge,
            .cannot_allocate_memory => return error.MemoryUnavailable,
            .operation_not_supported => return error.UnsupportedOperation,
            .resource_temporarily_unavailable => return error.WouldBlock,

            else => unreachable,
        }
    }
}

pub fn close(self: Self) void {
    _ = system.close(self.handle);
}

pub const Flags = packed struct(u1) {
    cloexec: bool = false,
};

pub fn getFlags(self: Self) !Flags {
    return @bitCast(@as(u1, @intCast(try fcntl(self, .getfd, 0))));
}

pub fn setFlags(self: Self, flags: Flags) !void {
    _ = try fcntl(self, .setfd, @intCast(@as(u1, @bitCast(flags))));
}

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

const Self = @This();
const std = @import("std");
const linux = std.os.linux;
const system = linux;
const io = @import("io.zig");
const errno = @import("errno.zig");
const Errno = errno.Errno;
