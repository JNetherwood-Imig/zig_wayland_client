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
) CreateError!Self {
    var sock_type: u32 = @intFromEnum(socket_type);
    if (options.nonblock) sock_type |= 0x800;
    if (options.cloexec) sock_type |= 0x80000;
    const ret = system.socket(
        @intFromEnum(domain),
        sock_type,
        if (protocol) |p| @bitCast(p.raw) else 0,
    );
    return switch (Errno.get(ret)) {
        .success => .{ .handle = .{ .handle = @intCast(ret) } },
        .address_family_not_supported_by_protocol => error.UnsupportedAddressFamily,
        .too_many_open_files => error.ProcessFdLimitReached,
        .too_many_open_files_in_system => error.SystemFdLimitReached,
        .protocol_not_supported => error.UnsupportedProtocolForAddressFamily,
        .protocol_wrong_type_for_socket => error.UnsupportedTypeForProtocol,
        .permission_denied => error.AccessDenied,
        .no_buffer_space_available => error.SystemResources,
        .cannot_allocate_memory => error.OutOfMemory,
        else => unreachable,
    };
}

pub fn close(self: Self) void {
    self.handle.close();
}

pub const ConnectUnixError = error{
    FileNotFound,
    ConnectionRefused,
    AccessDenied,
    WouldBlock,
    InProgress,
    AlreadyConnected,
    NotASocket,
    AddressNotAvailable,
    TimedOut,
    BadAddress,
};

pub fn connectUnix(self: Self, path: []const u8) ConnectUnixError!void {
    var addr = system.sockaddr.un{ .path = @splat(0) };
    @memcpy(addr.path[0..path.len], path);
    const ret = system.connect(self.handle.handle, &addr, @sizeOf(@TypeOf(addr)));
    return switch (Errno.get(ret)) {
        .success => {},
        .connection_refused => error.ConnectionRefused,
        .permission_denied => error.AccessDenied,
        .resource_temporarily_unavailable => error.WouldBlock,
        .operation_now_in_progress, .operation_already_in_progress => error.InProgress,
        .transport_endpoint_already_connected => error.AlreadyConnected,
        .no_such_file_or_directory => error.FileNotFound,
        .socket_operation_on_non_socket => error.NotASocket,
        .cannot_assign_requested_address => error.AddressNotAvailable,
        .connection_timed_out => error.TimedOut,
        .bad_address => error.BadAddress,
        else => unreachable,
    };
}

const Self = @This();
const std = @import("std");
const system = std.os.linux;
const File = @import("file.zig").File;
const Errno = @import("errno.zig").Errno;
