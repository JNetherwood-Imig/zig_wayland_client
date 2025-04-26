handle: File,

pub const Domain = enum(u32) {
    unix = 1,
    inet = 2,
    inet6 = 10,
    netlink = 16,
    packet = 17,
};

pub const Type = enum(u32) {
    stream = 1,
    dgram = 2,
    raw = 3,
    rdm = 4,
    seqpacket = 5,
    dccp = 6,
    packet = 10,
};

pub const Options = struct {
    nonblock: bool = false,
    cloexec: bool = false,
};

pub const Protocol = union {
    raw: u32,
    ipproto: enum(u32) {
        ip = 0,
        tcp = 6,
        udp = 17,
        icmp = 1,
        raw = 255,
    },
    eth_p: enum(u32) {
        all = 0x0003,
        ip = 0x0800,
    },
    netlink: enum(u32) {
        route = 0,
        kobject_uevent = 15,
        generic = 16,
        audit = 9,
    },
};

pub const CreateError = error{
    UnsupportedAddressFamily,
    ProcessFdLimitReached,
    SystemFdLimitReached,
    UnsupportedProtocolForAddressFamily,
    UnsupportedTypeForProtocol,
    AccessDenied,
    SystemResources,
    OutOfMemory,
};

pub fn create(
    domain: Domain,
    socket_type: Type,
    options: Options,
    protocol: ?Protocol,
) CreateError!Socket {
    var sock_type: u32 = @intFromEnum(socket_type);
    if (options.nonblock) sock_type |= 0x800;
    if (options.cloexec) sock_type |= 0x80000;
    const ret = system.socket(
        @intFromEnum(domain),
        sock_type,
        if (protocol) |p| @bitCast(p.raw) else 0,
    );
    return switch (errno(ret)) {
        .SUCCESS => .{ .handle = .{ .handle = @intCast(ret) } },
        .AFNOSUPPORT => error.UnsupportedAddressFamily,
        .MFILE => error.ProcessFdLimitReached,
        .NFILE => error.SystemFdLimitReached,
        .PROTONOSUPPORT => error.UnsupportedProtocolForAddressFamily,
        .PROTOTYPE => error.UnsupportedTypeForProtocol,
        .ACCES => error.AccessDenied,
        .NOBUFS => error.SystemResources,
        .NOMEM => error.OutOfMemory,
        else => unreachable,
    };
}

pub fn close(self: Socket) void {
    self.handle.close();
}

pub const ConnectUnixError = error{
    AddressNotAvailable,
    AddressFamilyNotSupported,
    RequestInProgress,
    BadFileDescriptor,
    ConnectionRefused,
    ConnectionInProgress,
    Interrupted,
    AlreadyConnected,
    NotASocket,
    DifferentProtocolType,
    TimedOut,
    IOError,
    SymLinkLoop,
    PathNameTooLong,
    FileNotFound,
    NotADirectory,
    AccessDenied,
    AddressInUse,
    ConnectionReset,
    InvalidArgument,
    OutOfBufferSpace,
    CannotConnectToSocket,
};

pub fn connectUnix(self: Socket, path: []const u8) ConnectUnixError!void {
    var addr = system.sockaddr.un{ .path = @splat(0) };
    @memcpy(addr.path[0..path.len], path);
    const ret = system.connect(self.handle.handle, &addr, @sizeOf(@TypeOf(addr)));
    return switch (errno(ret)) {
        .SUCCESS => {},
        .ADDRNOTAVAIL => error.AddressNotAvailable,
        .AFNOSUPPORT => error.AddressFamilyNotSupported,
        .ALREADY => error.RequestInProgress,
        .BADF => error.BadFileDescriptor,
        .CONNREFUSED => error.ConnectionRefused,
        .INPROGRESS => error.ConnectionInProgress,
        .INTR => error.Interrupted,
        .ISCONN => error.AlreadyConnected,
        .NOTSOCK => error.NotASocket,
        .PROTOTYPE => error.DifferentProtocolType,
        .TIMEDOUT => error.TimedOut,
        .IO => error.IOError,
        .LOOP => error.SymLinkLoop,
        .NAMETOOLONG => error.PathNameTooLong,
        .NOENT => error.FileNotFound,
        .NOTDIR => error.NotADirectory,
        .ACCES => error.AccessDenied,
        .ADDRINUSE => error.AddressInUse,
        .CONNRESET => error.ConnectionReset,
        .INVAL => error.InvalidArgument,
        .NOBUFS => error.OutOfBufferSpace,
        .OPNOTSUPP => error.CannotConnectToSocket,
        else => unreachable,
    };
}

const Socket = @This();

const std = @import("std");
const system = std.os.linux;
const errno = std.posix.errno;
const File = @import("file.zig").File;
