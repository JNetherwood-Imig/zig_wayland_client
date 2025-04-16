const std = @import("std");
const io = @import("io.zig");

pub const Errno = @import("posix/errno.zig").Errno;
pub const File = @import("posix/File.zig");
pub const Epoll = @import("posix/Epoll.zig");

test "file" {
    io.eprintln("Testing file functions...");

    const fd = try File.open("/dev/dri/card1", .{}, .{});
    defer fd.close();

    io.eprintlnf("GPU fd is {any}", .{fd});

    var flags = try fd.getFlags();
    io.eprintlnf("Old GPU fd flags are {any}", .{flags});
    flags.cloexec = true;
    try fd.setFlags(flags);
    io.eprintlnf("New GPU fd flags are {any}", .{flags});
}

test "epoll" {}

// pub const Pipe = struct {
//     handle: [2]Fd,

//     pub const CreateError = posix.PipeError;
//     pub inline fn create() CreateError!Pipe {
//         return .{ .handle = try posix.pipe() };
//     }

//     pub inline fn close(self: Pipe) void {
//         for (self.handle) |fd| posix.close(fd);
//     }

//     pub inline fn getReadFd(self: Pipe) Fd {
//         return self.handle[0];
//     }

//     pub inline fn getWriteFd(self: Pipe) Fd {
//         return self.handle[1];
//     }
// };

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
