pub const Sig = enum(u32) {
    hangup = SIG.HUP,
    interrupt = SIG.INT,
    quit = SIG.QUIT,
    illegal_instruction = SIG.ILL,
    trap = SIG.TRAP,
    aborted = SIG.ABRT,
    bus_error = SIG.BUS,
    floating_point_exception = SIG.FPE,
    kill = SIG.KILL,
    user_1 = SIG.USR1,
    segmentation_fault = SIG.SEGV,
    user_2 = SIG.USR2,
    broken_pipe = SIG.PIPE,
    alarm = SIG.ALRM,
    terminated = SIG.TERM,
    stack_fault = SIG.STKFLT,
    child_status_changed = SIG.CHLD,
    @"continue" = SIG.CONT,
    stop = SIG.STOP,
    stop_user = SIG.TSTP,
    stop_tty_in = SIG.TTIN,
    stop_tty_out = SIG.TTOU,
    urgent_io = SIG.URG,
    cpu_time_limit_exceeded = SIG.XCPU,
    file_size_limit_exceeded = SIG.XFSZ,
    virtual_timer_expired = SIG.VTALRM,
    profiling_timer_expired = SIG.PROF,
    io_possible = SIG.IO,
    power_failure = SIG.PWR,
    bad_syscall = SIG.SYS,
};

pub const Signals = packed struct {
    hangup: bool = false,
    interrupt: bool = false,
    quit: bool = false,
    illegal_instruction: bool = false,
    trap: bool = false,
    aborted: bool = false,
    bus_error: bool = false,
    floating_point_exception: bool = false,
    kill: bool = false,
    user_1: bool = false,
    segmentation_fault: bool = false,
    user_2: bool = false,
    broken_pipe: bool = false,
    alarm: bool = false,
    terminated: bool = false,
    stack_fault: bool = false,
    child_status_changed: bool = false,
    @"continue": bool = false,
    stop: bool = false,
    stop_user: bool = false,
    stop_tty_in: bool = false,
    stop_tty_out: bool = false,
    urgent_io: bool = false,
    cpu_time_limit_exceeded: bool = false,
    file_size_limit_exceeded: bool = false,
    virtual_timer_expired: bool = false,
    profiling_timer_expired: bool = false,
    io_possible: bool = false,
    power_failure: bool = false,
    bad_syscall: bool = false,
};

pub const Sigset = extern struct {
    data: system.sigset_t = system.empty_sigset,

    pub inline fn add(self: *Sigset, signal: Sig) void {
        system.sigaddset(&self.data, @intFromEnum(signal));
    }

    pub inline fn del(self: *Sigset, signal: Sig) void {
        system.sigdelset(&self.data, @intFromEnum(signal));
    }

    pub inline fn isMember(self: *const Sigset, signal: Sig) bool {
        return system.sigismember(&self.data, @intFromEnum(signal));
    }
};

pub const Signalfd = struct {
    handle: File,

    const Self = @This();

    pub const CreateFlags = packed struct(u32) {
        nonblock: bool = false,
        _: u9 = 0,
        cloexec: bool = false,

        pub fn toInt(self: CreateFlags, comptime T: type) T {
            switch (@typeInfo(T)) {
                .int => {},
                else => @compileError("Expected an int type for Signalfd.CreateFlags.toInt"),
            }
            return @as(T, @intCast(@as(u11, @bitCast(self)))) << @as(T, 13);
        }
    };

    pub const CreateError = error{};

    pub fn create(signals: Signals, flags: CreateFlags) CreateError!Self {
        var set = Sigset{};
        inline for (@typeInfo(Signals).@"struct".fields) |field|
            if (@field(signals, field.name))
                system.sigaddset(&set, @intFromEnum(@field(Sig, field.name)));

        system.sigprocmask(SIG.BLOCK, &set, null);

        const ret = system.signalfd(-1, &set, flags.toInt(u32));
        return switch (Errno.get(ret)) {
            .success => .{ .handle = @intCast(ret) },
            else => unreachable,
        };
    }

    pub fn close(self: Self) void {
        self.handle.close();
    }

    // pub const Siginfo = union(Sig) {
    //     hangup: struct { code: i32 },
    //     interrupt: struct { code: i32 },
    //     quit: struct { code: i32 },
    //     illegal_instruction: struct { code: i32 },
    //     trap: struct { code: i32 },
    //     aborted: struct { code: i32 },
    //     bus_error: struct { code: i32 },
    //     floating_point_exception: struct { code: i32 },
    //     kill: struct { code: i32 },
    //     user_1: struct { code: i32 },
    //     segmentation_fault: struct { code: i32 },
    //     user_2: struct { code: i32 },
    //     broken_pipe: struct { code: i32 },
    //     alarm: struct { code: i32 },
    //     terminated: struct { code: i32 },
    //     stack_fault: struct { code: i32 },
    //     child_status_changed: struct { code: i32 },
    //     @"continue": struct { code: i32 },
    //     stop: struct { code: i32 },
    //     stop_user: struct { code: i32 },
    //     stop_tty_in: struct { code: i32 },
    //     stop_tty_out: struct { code: i32 },
    //     urgent_io: struct { code: i32 },
    //     cpu_time_limit_exceeded: struct { code: i32 },
    //     file_size_limit_exceeded: struct { code: i32 },
    //     virtual_timer_expired: struct { code: i32 },
    //     profiling_timer_expired: struct { code: i32 },
    //     io_possible: struct { code: i32 },
    //     power_failure: struct { code: i32 },
    //     bad_syscall: struct { code: i32 },
    // };

    pub const Siginfo = system.signalfd_siginfo;

    pub const ReadError = error{Incomplete} || std.fs.File.ReadError;

    pub fn read(self: Signalfd) ReadError!Siginfo {
        var info: Siginfo = undefined;
        const bytes_read = try self.handle.toStdFile().read(
            @as([*]u8, @ptrCast(@alignCast(&info)))[0..@sizeOf(@TypeOf(info))],
        );
        if (bytes_read != @sizeOf(@TypeOf(info))) return error.Incomplete;
        return info;
    }
};

const std = @import("std");
const system = std.os.linux;
const SIG = system.SIG;
const File = @import("file.zig").File;
const Errno = @import("errno.zig").Errno;
