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
        FilesystemBusy,
        DiskQuotaExceeded,
        FileExists,
        BadAddress,
        Interrupted,
        InvalidArgument,
        IsADirectory,
        SymLinkLoop,
        ProcessFdLimitReached,
        PathNameTooLong,
        SystemFdLimitReached,
        DeviceNotFound,
        FileNotFound,
        OutOfMemory,
        FilesystemFull,
        NotADirectory,
        TemporaryFileNotSupported,
        FileTooBig,
        ReadOnlyFilesystem,
        TextFileBusy,
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
        return switch (errno(ret)) {
            .SUCCESS => .{ .handle = @intCast(ret) },
            .ACCES, .PERM => error.AccessDenied,
            .BUSY => error.FilesystemBusy,
            .DQUOT => error.DiskQuotaExceeded,
            .EXIST => error.FileExists,
            .FAULT => error.BadAddress,
            .INTR => error.Interrupted,
            .INVAL => error.InvalidArgument,
            .ISDIR => error.IsADirectory,
            .LOOP => error.SymLinkLoop,
            .MFILE => error.ProcessFdLimitReached,
            .NAMETOOLONG => error.PathNameTooLong,
            .NFILE => error.SystemFdLimitReached,
            .NODEV, .NXIO => error.DeviceNotFound,
            .NOENT => error.FileNotFound,
            .NOMEM => error.OutOfMemory,
            .NOSPC => error.FilesystemFull,
            .NOTDIR => error.NotADirectory,
            .OPNOTSUPP => error.TemporaryFileNotSupported,
            .FBIG, .OVERFLOW => error.FileTooBig,
            .ROFS => error.ReadOnlyFilesystem,
            .TXTBSY => error.TextFileBusy,
            .AGAIN => error.WouldBlock,
            else => unreachable,
        };
    }

    pub fn close(self: File) void {
        _ = system.close(self.handle);
    }

    pub const DupeError = error{
        ProcessFdLimitReached,
    } || BaseFcntlError;

    pub fn dupe(self: File) DupeError!File {
        const ret = self.fcntl(.dupfd, 0);
        return switch (errno(ret)) {
            .SUCCESS => .{ .handle = @intCast(ret) },
            .BADF => error.BadFileDescriptor,
            .MFILE => error.ProcessFdLimitReached,
            else => unreachable,
        };
    }

    pub const Flags = packed struct(u1) {
        cloexec: bool = false,
    };

    pub const GetFlagsError = BaseFcntlError;

    pub fn getFlags(self: File) GetFlagsError!Flags {
        const ret = self.fcntl(.getfd, 0);
        return switch (errno(ret)) {
            .SUCCESS => @bitCast(@as(u1, @intCast(ret))),
            .BADF => error.BadFileDescriptor,
            else => unreachable,
        };
    }

    pub const SetFlagsError = BaseFcntlError;

    pub fn setFlags(self: File, flags: Flags) SetFlagsError!void {
        const int_flags = @as(usize, @intCast(@as(u1, @bitCast(flags))));
        const ret = self.fcntl(.setfd, int_flags);
        return switch (errno(ret)) {
            .SUCCESS => {},
            .BADF => error.BadFileDescriptor,
            else => unreachable,
        };
    }

    pub fn isValid(self: File) bool {
        _ = self.getFlags() catch return false;
        return true;
    }

    pub const ReadError = error{
        WouldBlock,
        BadFileDescriptor,
        BadAddress,
        Interrupted,
        InvalidArgument,
        IOError,
        IsADirectory,
    };

    pub fn read(self: File, buf: []u8) ReadError!usize {
        const ret = system.read(self.handle, buf.ptr, buf.len);
        return switch (errno(ret)) {
            .SUCCESS => @intCast(ret),
            .AGAIN => error.WouldBlock,
            .BADF => error.BadFileDescriptor,
            .FAULT => error.BadAddress,
            .INTR => error.Interrupted,
            .INVAL => error.InvalidArgument,
            .IO => error.IOError,
            .ISDIR => error.IsADirectory,
            else => unreachable,
        };
    }

    pub const WriteError = error{
        WouldBlock,
        BadFileDescriptor,
        AddressNotSpecified,
        DiskQuotaExceeded,
        BadAddress,
        FileTooBig,
        Interrupted,
        InvalidArgument,
        IOError,
        FilesystemFull,
        AccessDenied,
        BrokenPipe,
    };

    pub fn write(self: File, bytes: []const u8) WriteError!usize {
        const ret = system.write(self.handle, bytes.ptr, bytes.len);
        return switch (errno(ret)) {
            .SUCCESS => @intCast(ret),
            .AGAIN => error.WouldBlock,
            .BADF => error.BadFileDescriptor,
            .DESTADDRREQ => error.AddressNotSpecified,
            .DQUOT => error.DiskQuotaExceeded,
            .FAULT => error.BadAddress,
            .FBIG => error.FileTooBig,
            .INTR => error.Interrupted,
            .INVAL => error.InvalidArgument,
            .IO => error.IOError,
            .NOSPC => error.FilesystemFull,
            .PERM => error.AccessDenied,
            .PIPE => error.BrokenPipe,
            else => unreachable,
        };
    }

    pub fn writeAll(self: File, bytes: []const u8) WriteError!void {
        var index: usize = 0;
        while (index < bytes.len) {
            index += try self.write(bytes[index..]);
        }
    }

    pub const CmsgType = enum(i32) {
        rights = 0x01,
        credentials = 0x02,
        security = 0x03,
        pidfd = 0x04,
    };

    pub const MessageFlags = struct {
        oob: bool = false,
        peek: bool = false,
        dontroute: bool = false,
        ctruc: bool = false,
        proxy: bool = false,
        truc: bool = false,
        dontwait: bool = false,
        eor: bool = false,
        waitall: bool = false,
        fin: bool = false,
        syn: bool = false,
        confirm: bool = false,
        rst: bool = false,
        errqueue: bool = false,
        nosignal: bool = false,
        more: bool = false,
        waitforone: bool = false,
        batch: bool = false,
        zerocopy: bool = false,
        fastopen: bool = false,
        cmsg_cloexec: bool = false,

        pub fn toInt(self: MessageFlags, comptime T: type) T {
            switch (@typeInfo(T)) {
                .int => {},
                else => unreachable,
            }

            var flags: T = 0;
            if (self.oob) flags |= system.MSG.OOB;
            if (self.peek) flags |= system.MSG.PEEK;
            if (self.dontroute) flags |= system.MSG.DONTROUTE;
            if (self.ctruc) flags |= system.MSG.CTRUNC;
            if (self.proxy) flags |= system.MSG.PROXY;
            if (self.truc) flags |= system.MSG.TRUNC;
            if (self.dontwait) flags |= system.MSG.DONTWAIT;
            if (self.eor) flags |= system.MSG.EOR;
            if (self.waitall) flags |= system.MSG.WAITALL;
            if (self.fin) flags |= system.MSG.FIN;
            if (self.syn) flags |= system.MSG.SYN;
            if (self.confirm) flags |= system.MSG.CONFIRM;
            if (self.rst) flags |= system.MSG.RST;
            if (self.errqueue) flags |= system.MSG.ERRQUEUE;
            if (self.nosignal) flags |= system.MSG.NOSIGNAL;
            if (self.more) flags |= system.MSG.MORE;
            if (self.waitforone) flags |= system.MSG.WAITFORONE;
            if (self.batch) flags |= system.MSG.BATCH;
            if (self.zerocopy) flags |= system.MSG.ZEROCOPY;
            if (self.fastopen) flags |= system.MSG.FASTOPEN;
            if (self.cmsg_cloexec) flags |= system.MSG.CMSG_CLOEXEC;

            return flags;
        }
    };

    pub const SendMessageError = error{
        WouldBlock,
        AddressFamilyNotSupported,
        BadFileDescriptor,
        ConnectionReset,
        Interrupted,
        IovLenOverflow,
        MessageTooLarge,
        NotConnected,
        NotASocket,
        UnsupportedFlagsForSocket,
        BrokenPipe,
        IOError,
        SymLinkLoop,
        PathNameTooLong,
        FileNotFound,
        NotADirectory,
        AccessDenied,
        NoAddressSpecified,
        AlreadyConnected,
        OutOfBufferSpace,
        OutOfMemory,
    };

    pub fn sendMessage(
        self: File,
        comptime T: type,
        control_data: T,
        cmsg_type: CmsgType,
        bytes: []const u8,
        flags: MessageFlags,
    ) SendMessageError!usize {
        const iov = std.posix.iovec_const{ .base = bytes.ptr, .len = bytes.len };
        var cmsg_buf = [_]u8{0} ** (@sizeOf(CmsgHdr) + @sizeOf(T));
        serializeCmsg(&cmsg_buf, T, control_data, cmsg_type);
        const msg = system.msghdr_const{
            .name = null,
            .namelen = 0,
            .iov = @ptrCast(&iov),
            .iovlen = 1,
            .control = &cmsg_buf,
            .controllen = cmsg_buf.len,
            .flags = 0,
        };

        const ret = system.sendmsg(self.handle, &msg, flags.toInt(u32));
        return switch (errno(ret)) {
            .SUCCESS => @intCast(ret),
            .AGAIN => error.WouldBlock,
            .AFNOSUPPORT => error.AddressFamilyNotSupported,
            .BADF => error.BadFileDescriptor,
            .CONNRESET => error.ConnectionReset,
            .INTR => error.Interrupted,
            .INVAL => error.IovLenOverflow,
            .MSGSIZE => error.MessageTooLarge,
            .NOTCONN => error.NotConnected,
            .NOTSOCK => error.NotASocket,
            .OPNOTSUPP => error.UnsupportedFlagsForSocket,
            .PIPE => error.BrokenPipe,
            .IO => error.IOError,
            .LOOP => error.SymLinkLoop,
            .NAMETOOLONG => error.PathNameTooLong,
            .NOENT => error.FileNotFound,
            .NOTDIR => error.NotADirectory,
            .ACCES => error.AccessDenied,
            .DESTADDRREQ => error.NoAddressSpecified,
            .ISCONN => error.AlreadyConnected,
            .NOBUFS => error.OutOfBufferSpace,
            .NOMEM => error.OutOfMemory,
            else => unreachable,
        };
    }

    pub fn recieveMessage(self: File, comptime T: type, out_data: *T, buf: []u8, flags: u32) !usize {
        var iov = std.posix.iovec{ .base = buf.ptr, .len = buf.len };
        var cmsg_buf = [_]u8{0} ** (@sizeOf(CmsgHdr) + @sizeOf(T));
        var msg = system.msghdr{
            .name = null,
            .namelen = 0,
            .iov = @ptrCast(&iov),
            .iovlen = 1,
            .control = &cmsg_buf,
            .controllen = cmsg_buf.len,
            .flags = 0,
        };
        const ret = system.recvmsg(self.handle, &msg, flags);
        return switch (errno(ret)) {
            .SUCCESS => ret: {
                out_data.* = std.mem.bytesToValue(T, cmsg_buf[@sizeOf(CmsgHdr)..]);
                break :ret @intCast(ret);
            },
            else => unreachable,
        };
    }

    const CmsgHdr = extern struct {
        length: usize,
        level: i32,
        type: i32,
    };

    fn serializeCmsg(
        buf: []u8,
        comptime T: type,
        data: T,
        cmsg_type: CmsgType,
    ) void {
        const sol_rights = 1;
        const len = @sizeOf(CmsgHdr) + @sizeOf(T);
        const head = CmsgHdr{
            .length = len,
            .level = sol_rights,
            .type = @intFromEnum(cmsg_type),
        };
        @as(*CmsgHdr, @ptrCast(@alignCast(&buf[0]))).* = head;
        @as(*T, @ptrCast(@alignCast(&buf[@sizeOf(CmsgHdr)]))).* = data;
    }

    const FcntlCommand = enum(u32) {
        dupfd = system.F.DUPFD,
        getfd = system.F.GETFD,
        setfd = system.F.SETFD,
    };

    inline fn fcntl(fd: File, cmd: FcntlCommand, arg: usize) usize {
        return system.fcntl(fd.handle, @intCast(@intFromEnum(cmd)), arg);
    }

    const BaseFcntlError = error{
        BadFileDescriptor,
    };
};

const std = @import("std");
const system = std.os.linux;
const errno = std.posix.errno;
