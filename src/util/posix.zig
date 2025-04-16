const std = @import("std");
const system = std.os.linux;
const io = @import("io.zig");

pub const Errno = @import("posix/errno.zig").Errno;
pub const File = @import("posix/File.zig");
pub const Epoll = @import("posix/Epoll.zig");
pub const Pipe = @import("posix/Pipe.zig");
pub const Fd = File.Fd;

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
        @intCast(@as(u32, @bitCast(mode))),
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

test "file" {
    io.eprintln("Testing file functions...");

    const fd = try open("/dev/dri/card1", .{}, .{});
    defer fd.close();

    io.eprintlnf("GPU fd is {any}", .{fd});

    var flags = try fd.getFlags();
    io.eprintlnf("Old GPU fd flags are {any}", .{flags});
    flags.cloexec = true;
    try fd.setFlags(flags);
    io.eprintlnf("New GPU fd flags are {any}", .{flags});
}

test "epoll" {
    io.eprintln("Testing epoll...");
    const fd = try open("/dev/dri/card1", .{}, .{});
    defer fd.close();

    const epoll = try Epoll.create(.{});
    defer epoll.close();

    try epoll.add(fd.handle, .{
        .events = .{ .in = true },
        .data = .{ .fd = fd.handle },
    });
    try epoll.mod(fd.handle, .{
        .events = .{ .out = true },
        .data = .{ .fd = fd.handle },
    });

    var events = [1]Epoll.Event{undefined};
    const count = try epoll.wait(&events, 10);
    io.eprintlnf("Got {d} events", .{count});

    try epoll.del(fd.handle);
}

test "pipe" {
    io.eprintln("Testing pipe...");
    const pipe = try Pipe.create();
    defer pipe.close();

    const read = pipe.getReadFile();
    const write = pipe.getWriteFile();

    io.eprintlnf(
        "Pipe read file is {any} and write file is {any}",
        .{ read, write },
    );
}

// pub const Sig = enum(u32) {
//     hangup = SIG.HUP,
//     interrupt = SIG.INT,
//     quit = SIG.QUIT,
//     illegal_instruction = SIG.ILL,
//     trap = SIG.TRAP,
//     aborted = SIG.ABRT,
//     bus_error = SIG.BUS,
//     floating_point_exception = SIG.FPE,
//     kill = SIG.KILL,
//     user_1 = SIG.USR1,
//     segmentation_fault = SIG.SEGV,
//     user_2 = SIG.USR2,
//     broken_pipe = SIG.PIPE,
//     alarm = SIG.ALRM,
//     terminated = SIG.TERM,
//     stack_fault = SIG.STKFLT,
//     child_status_changed = SIG.CHLD,
//     @"continue" = SIG.CONT,
//     stop = SIG.STOP,
//     stop_user = SIG.TSTP,
//     stop_tty_in = SIG.TTIN,
//     stop_tty_out = SIG.TTOU,
//     urgent_io = SIG.URG,
//     cpu_time_limit_exceeded = SIG.XCPU,
//     file_size_limit_exceeded = SIG.XFSZ,
//     virtual_timer_expired = SIG.VTALRM,
//     profiling_timer_expired = SIG.PROF,
//     io_possible = SIG.IO,
//     power_failure = SIG.PWR,
//     bad_syscall = SIG.SYS,
// };

// pub const Signalfd = struct {
//     handle: Fd,

//     pub const Signals = packed struct {
//         hangup: bool = false,
//         interrupt: bool = false,
//         quit: bool = false,
//         illegal_instruction: bool = false,
//         trap: bool = false,
//         aborted: bool = false,
//         bus_error: bool = false,
//         floating_point_exception: bool = false,
//         kill: bool = false,
//         user_1: bool = false,
//         segmentation_fault: bool = false,
//         user_2: bool = false,
//         broken_pipe: bool = false,
//         alarm: bool = false,
//         terminated: bool = false,
//         stack_fault: bool = false,
//         child_status_changed: bool = false,
//         @"continue": bool = false,
//         stop: bool = false,
//         stop_user: bool = false,
//         stop_tty_in: bool = false,
//         stop_tty_out: bool = false,
//         urgent_io: bool = false,
//         cpu_time_limit_exceeded: bool = false,
//         file_size_limit_exceeded: bool = false,
//         virtual_timer_expired: bool = false,
//         profiling_timer_expired: bool = false,
//         io_possible: bool = false,
//         power_failure: bool = false,
//         bad_syscall: bool = false,
//     };

//     pub const CreateError = error{
//         SystemFdQuotaExceeded,
//         SystemResources,
//         ProcessResources,
//         InodeMountFail,
//     };

//     pub fn create(signals: Signals) CreateError!Signalfd {
//         var set: linux.sigset_t = linux.empty_sigset;
//         inline for (@typeInfo(Signals).@"struct".fields) |field|
//             if (@field(signals, field.name))
//                 linux.sigaddset(&set, @intFromEnum(@field(Sig, field.name)));

//         posix.sigprocmask(SIG.BLOCK, &set, null);

//         const fd = posix.signalfd(-1, &set, linux.SFD.NONBLOCK) catch |err|
//             return switch (err) {
//                 error.SystemFdQuotaExceeded => error.SystemFdQuotaExceeded,
//                 error.SystemResources => error.SystemResources,
//                 error.ProcessResources => error.ProcessResources,
//                 error.InodeMountFail => error.InodeMountFail,
//                 error.Unexpected => unreachable,
//             };
//         return .{ .handle = fd };
//     }

//     pub fn close(self: Signalfd) void {
//         posix.close(self.handle);
//     }

//     pub const Siginfo = posix.siginfo_t;

//     pub const ReadError = error{Incomplete} || posix.ReadError;

//     pub fn read(self: Signalfd) ReadError!Siginfo {
//         var info: Siginfo = undefined;
//         const bytes_read = try posix.read(
//             self.handle,
//             @as([*]u8, @ptrCast(@alignCast(&info)))[0..@sizeOf(Siginfo)],
//         );
//         if (bytes_read != @sizeOf(Siginfo)) return error.Incomplete;
//         return info;
//     }
// };
