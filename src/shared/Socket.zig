handle: Handle,

pub const InitDisplayError = std.posix.SocketError ||
    std.posix.ConnectError ||
    std.fmt.BufPrintError ||
    error{NoXdgRuntimeDir};

pub fn initDisplay(display: []const u8) InitDisplayError!Socket {
    const sockfd = try std.posix.socket(
        std.posix.AF.UNIX,
        std.posix.SOCK.STREAM | std.posix.SOCK.CLOEXEC | std.posix.SOCK.NONBLOCK,
        0,
    );
    const self = Socket{ .handle = sockfd };
    errdefer self.close();
    var addr = std.posix.sockaddr.un{ .path = @splat(0) };
    if (std.fs.path.isAbsolute(display)) {
        @memcpy(addr.path[0..display.len], display);
    } else {
        const xdg_runtime_dir = std.posix.getenv("XDG_RUNTIME_DIR") orelse return error.NoXdgRuntimeDir;
        try std.fmt.bufPrintZ(addr.path, "{s}/{s}", .{ xdg_runtime_dir, display });
    }
    try std.posix.connect(sockfd, &addr, @sizeOf(@TypeOf(addr)));
    return self;
}

pub const InitFdError = std.posix.FcntlError;

pub fn initFd(fd: i32) InitFdError!Socket {
    var flags = try std.posix.fcntl(fd, std.posix.F.GETFD, 0);
    flags |= std.posix.FD_CLOEXEC;
    _ = try std.posix.fcntl(fd, std.posix.F.SETFD, flags);
    return Socket{ .handle = fd };
}

pub inline fn close(self: Socket) void {
    std.posix.close(self.handle);
}

pub const ReadError = std.posix.ReadError;

pub inline fn read(self: Socket, buf: []u8) ReadError!usize {
    return std.posix.read(self.handle, buf);
}

pub const PeekError = std.posix.RecvFromError;

pub inline fn peek(self: Socket, buf: []u8) PeekError!usize {
    return std.posix.recv(self.handle, buf, std.posix.MSG.PEEK);
}

pub const WriteError = std.posix.WriteError;

pub inline fn write(self: Socket, bytes: []const u8) WriteError!usize {
    return std.posix.write(self.handle, bytes);
}

pub inline fn writeAll(self: Socket, bytes: []const u8) WriteError!void {
    var written = try self.write(bytes);
    while (written < bytes.len) {
        written += try self.write(bytes[written..]);
    }
}

pub const RecieveFdsError = RecvmsgError;

pub fn recieveWithFds(self: Socket, fd_buf: []std.posix.fd_t, buf: []u8) RecieveFdsError!usize {
    var hdr: std.os.linux.msghdr = undefined;
    const recieved = try self.recvmsg(&hdr);
    @memcpy(fd_buf, hdr.control);
    @memcpy(buf, hdr.iov[0].base);
    return recieved;
}

pub const SendFdsError = SendmsgError;

pub fn sendWithFds(self: Socket, fds: []const std.posix.fd_t, bytes: []const u8) SendFdsError!usize {
    const msg = std.posix.msghdr_const{
        .iov = &.{std.posix.iovec_const{ .base = bytes.ptr, .len = bytes.len }},
        .iovlen = 1,
        .control = fds.ptr,
        .controllen = @sizeOf(fds),
        .flags = 0,
    };

    return self.sendmsg(msg);
}

const RecvmsgError = error{};

fn recvmsg(socket: Socket, msghdr: *std.posix.msghdr) RecvmsgError!usize {
    const ret = std.os.linux.recvmsg(socket.handle, msghdr, 0);
    return switch (std.posix.errno(ret)) {
        .SUCCESS => ret,
        else => unreachable,
    };
}

const SendmsgError = error{};

fn sendmsg(self: Socket, msg: *const std.posix.msghdr_const) SendmsgError!usize {
    const ret = std.os.linux.sendmsg(self.handle, msg, 0);
    return switch (std.posix.errno(ret)) {
        .SUCCESS => ret,
        else => unreachable,
    };
}

const Socket = @This();

const std = @import("std");
const Handle = std.posix.socket_t;
