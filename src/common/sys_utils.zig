const std = @import("std");
const posix = std.posix;
const linux = std.os.linux;
pub const Fd = posix.fd_t;

pub const Epoll = struct {
    handle: Fd,

    pub const CreateError = posix.EpollCreateError;
    pub inline fn create(flags: u32) CreateError!Epoll {
        return .{ .handle = try posix.epoll_create1(flags) };
    }

    pub inline fn close(self: Epoll) void {
        posix.close(self.handle);
    }

    pub const Ctl = enum(u2) {
        add = linux.EPOLL.CTL_ADD,
        del = linux.EPOLL.CTL_DEL,
        mod = linux.EPOLL.CTL_MOD,
    };

    pub const Events = packed struct(u32) {
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
        _: u22 = 0,
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

    pub const CtlError = posix.EpollCtlError;
    pub inline fn ctl(self: Epoll, op: Ctl, fd: Fd, event: ?Event) CtlError!void {
        var ev = event;
        return try posix.epoll_ctl(self.handle, @intFromEnum(op), fd, @ptrCast(&ev));
    }

    pub const WaitError = error{
        BadAddress,
        InterruptedSystemCall,
        Unexpected,
    };
    pub inline fn wait(self: Epoll, events: []Event, timeout: i32) WaitError!usize {
        const ret = linux.epoll_wait(self.handle, @ptrCast(events.ptr), events.len, timeout);
        return switch (posix.errno(ret)) {
            .SUCCESS => ret,
            .FAULT => error.BadAddress,
            .INTR => error.InterruptedSystemCall,
            .BADF, .INVAL => unreachable,
            else => error.Unexpected,
        };
    }
};

pub const Pipe = struct {
    handle: [2]Fd,

    pub const CreateError = posix.PipeError;
    pub inline fn create() CreateError!Pipe {
        return .{ .handle = try posix.pipe() };
    }

    pub inline fn close(self: Pipe) void {
        for (self.handle) |fd| posix.close(fd);
    }

    pub inline fn getReadFd(self: Pipe) Fd {
        return self.handle[0];
    }

    pub inline fn getWriteFd(self: Pipe) Fd {
        return self.hadnle[1];
    }
};

pub const Signalfd = struct {
    handle: Fd,

    pub const Signals = struct {
        hangup: bool = false,
        interrupt: bool = false,
        quit: bool = false,
        illegal_instruction: bool = false,
        trap: bool = false,
        aborted: bool = false,
        bus_error: bool = false,
        float_exception: bool = false,
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
        cpu_time_limit: bool = false,
        file_size_limit: bool = false,
        virtual_timer: bool = false,
        profiling_timer: bool = false,
        io_possible: bool = false,
        power_failure: bool = false,
        bad_syscall: bool = false,
    };

    pub const CreateError = error{
        SystemFdQuotaExceeded,
        SystemResources,
        ProcessResources,
        InodeMountFail,
    };

    pub fn create(comptime signals: Signals) CreateError!Signalfd {
        const SIG = linux.SIG;
        var set: linux.sigset_t = linux.empty_sigset;
        if (signals.hangup) linux.sigaddset(&set, SIG.HUP);
        if (signals.interrupt) linux.sigaddset(&set, SIG.INT);
        if (signals.quit) linux.sigaddset(&set, SIG.QUIT);
        if (signals.illegal_instruction) linux.sigaddset(&set, SIG.ILL);
        if (signals.trap) linux.sigaddset(&set, SIG.TRAP);
        if (signals.aborted) linux.sigaddset(&set, SIG.ABRT);
        if (signals.bus_error) linux.sigaddset(&set, SIG.BUS);
        if (signals.float_exception) linux.sigaddset(&set, SIG.FPE);
        if (signals.kill) linux.sigaddset(&set, SIG.KILL);
        if (signals.user_1) linux.sigaddset(&set, SIG.USR1);
        if (signals.segmentation_fault) linux.sigaddset(&set, SIG.SEGV);
        if (signals.user_2) linux.sigaddset(&set, SIG.USR2);
        if (signals.broken_pipe) linux.sigaddset(&set, SIG.PIPE);
        if (signals.alarm) linux.sigaddset(&set, SIG.ALRM);
        if (signals.terminated) linux.sigaddset(&set, SIG.TERM);
        if (signals.stack_fault) linux.sigaddset(&set, SIG.STKFLT);
        if (signals.child_status_changed) linux.sigaddset(&set, SIG.CHLD);
        if (signals.@"continue") linux.sigaddset(&set, SIG.CONT);
        if (signals.stop) linux.sigaddset(&set, SIG.STOP);
        if (signals.stop_user) linux.sigaddset(&set, SIG.TSTP);
        if (signals.stop_tty_in) linux.sigaddset(&set, SIG.TTIN);
        if (signals.stop_tty_out) linux.sigaddset(&set, SIG.TTOU);
        if (signals.urgent_io) linux.sigaddset(&set, SIG.URG);
        if (signals.cpu_time_limit) linux.sigaddset(&set, SIG.XCPU);
        if (signals.file_size_limit) linux.sigaddset(&set, SIG.XFSZ);
        if (signals.virtual_timer) linux.sigaddset(&set, SIG.VTALRM);
        if (signals.profiling_timer) linux.sigaddset(&set, SIG.PROF);
        if (signals.io_possible) linux.sigaddset(&set, SIG.IO);
        if (signals.power_failure) linux.sigaddset(&set, SIG.PWR);
        if (signals.bad_syscall) linux.sigaddset(&set, SIG.SYS);

        posix.sigprocmask(SIG.BLOCK, &set, null);

        return .{ .handle = try posix.signalfd(-1, &set, linux.SFD.NONBLOCK) };
    }

    pub fn close(self: Signalfd) void {
        posix.close(self.handle);
    }

    pub const Siginfo = posix.siginfo_t;

    pub const ReadError = error{Incomplete} || posix.ReadError;

    pub fn read(self: Signalfd) Siginfo {
        var info: Siginfo = undefined;
        const bytes_read = try posix.read(self.handle, @as([*]u8, @ptrCast(@alignCast(&info)))[0..@sizeOf(Siginfo)]);
        if (bytes_read != @sizeOf(Siginfo)) return error.Incomplete;
        return info;
    }
};
