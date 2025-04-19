pub const File = packed struct(i32) {
    handle: i32,

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
        none = 0,
        fifo = 1,
        character_device = 2,
        directory = 4,
        block_device = 6,
        regular = 8,
        link = 10,
        socket = 12,
    };

    pub const Mode = packed struct(u16) {
        other_access: Access = .{},
        group_access: Access = .{},
        owner_access: Access = .{},
        sticky: bool = false,
        set_gid: bool = false,
        set_uid: bool = false,
        type: Type = .none,
    };

    // TODO better OpenOptions, ideally split into 3 or 4 function args
    // access_mode: File.AccessMode, ...
    pub const OpenOptions = packed struct(u32) {
        access_mode: File.AccessMode = .read_only,
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

    pub const OpenError = error{
        AccessDenied,
        FileExists,
        FileNotFound,
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
        OutOfMemory,
        UnsupportedOperation,
        Interrupted,
        WouldBlock,
    };

    pub fn open(
        path: [:0]const u8,
        options: OpenOptions,
        mode: File.Mode,
    ) OpenError!File {
        const ret = system.open(
            path,
            @bitCast(options),
            @intCast(@as(u16, @bitCast(mode))),
        );
        return switch (Errno.get(ret)) {
            .success => .{ .handle = @intCast(ret) },
            .interrupted_system_call => error.Interrupted,
            .permission_denied => error.AccessDenied,
            .operation_not_permitted => error.AccessDenied,
            .file_exists => error.FileExists,
            .no_such_file_or_directory => error.FileNotFound,
            .no_such_device => error.FileNotFound,
            .no_such_device_or_address => error.FileNotFound,
            .file_name_too_long => error.PathTooLong,
            .too_many_levels_of_symbolic_links => error.SymLinkLoop,
            .is_a_directory => error.IsDirectory,
            .invalid_argument => error.InvalidArgument,
            .value_too_large_for_defined_data_type => error.InvalidArgument,
            .device_or_resource_busy => error.FilesystemBusy,
            .text_file_busy => error.FilesystemBusy,
            .no_space_left_on_device => error.FilesystemFull,
            .disk_quota_exceeded => error.FilesystemFull,
            .read_only_file_system => error.ReadOnlyFilesystem,
            .too_many_open_files => error.TooManyOpenFiles,
            .too_many_open_files_in_system => error.TooManyOpenFiles,
            .bad_file_descriptor => error.BadDescriptor,
            .bad_address => error.BadAddress,
            .file_too_large => error.FileTooLarge,
            .cannot_allocate_memory => error.OutOfMemory,
            .operation_not_supported => error.UnsupportedOperation,
            .resource_temporarily_unavailable => error.WouldBlock,
            else => unreachable,
        };
    }

    pub fn close(self: Self) void {
        _ = system.close(self.handle);
    }

    pub const DupeError = error{
        ProcessFdLimitReached,
    } || BaseFcntlError;

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

    pub fn getFlags(self: Self) GetFlagsError!Flags {
        const ret = self.fcntl(.getfd, 0);
        return switch (Errno.get(ret)) {
            .success => @bitCast(@as(u1, @intCast(ret))),
            .bad_file_descriptor => error.BadFileDescriptor,
            else => unreachable,
        };
    }

    pub const SetFlagsError = BaseFcntlError;

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

    pub fn getStatus(self: Self) GetStatusError!Mode {
        _ = self;
        return .{};
    }

    pub const SetStatusError = BaseFcntlError;

    pub fn setStatus(self: Self, status: Mode) SetStatusError!void {
        _ = self;
        _ = status;
    }

    pub const GetLockError = BaseFcntlError;

    pub fn getLock(self: Self) GetLockError!void {
        _ = self;
    }

    pub const TryLockError = BaseFcntlError;

    pub fn tryLock(self: Self) TryLockError!void {
        _ = self;
    }

    pub const SetLockError = BaseFcntlError;

    pub fn setLock(self: Self) SetLockError!void {
        _ = self;
    }

    pub const SetOwnError = BaseFcntlError;

    pub fn setOwn(self: Self) SetOwnError!void {
        _ = self;
    }

    pub const GetOwnError = BaseFcntlError;

    pub fn getOwn(self: Self) GetOwnError!void {
        _ = self;
    }

    pub const SetSigError = BaseFcntlError;

    pub fn setSig(self: Self) SetSigError!void {
        _ = self;
    }

    pub const GetSigError = BaseFcntlError;

    pub fn getSig(self: Self) GetSigError!void {
        _ = self;
    }

    pub const SetOwnExError = BaseFcntlError;

    pub fn setOwnEx(self: Self) SetOwnExError!void {
        _ = self;
    }

    pub const GetOwnExError = BaseFcntlError;

    pub fn getOwnEx(self: Self) GetOwnExError!void {
        _ = self;
    }

    pub const GetOwnerUidsError = BaseFcntlError;

    pub fn getOwnerUids(self: Self) GetOwnerUidsError!void {
        _ = self;
    }

    pub inline fn toStdFile(self: Self) std.fs.File {
        return std.fs.File{ .handle = self.handle };
    }

    pub inline fn fromStdFile(file: std.fs.File) Self {
        return File{ .handle = file.handle };
    }

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

    const Self = @This();
};

const std = @import("std");
const linux = std.os.linux;
const system = linux;
const io = @import("../io.zig");
const errno = @import("errno.zig");
const Errno = errno.Errno;
