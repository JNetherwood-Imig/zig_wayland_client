const std = @import("std");
const Self = @This();

socket: std.net.Stream,

pub const Error = error{
    BadWaylandSocketFd,
    FailedToSetSocketFlags,
    NoXdgRuntimeDir,
    DisplayPathTooLong,
    FailedToCreateSocket,
    FailedToConnectToSocket,
};

pub const ConnectInfo = union(enum) {
    socket: i32,
    display: []const u8,
};

pub fn init(connect_info: ConnectInfo) Error!Self {
    return switch (connect_info) {
        .socket => |socket| init: {
            var flags = std.os.linux.fcntl(socket, std.posix.F.GETFD, 0);
            const err = std.posix.errno(flags);
            if (err == .BADF) return error.BadWaylandSocketFd;
            flags |= std.posix.FD_CLOEXEC;
            _ = std.posix.fcntl(socket, std.posix.F.SETFD, flags) catch
                return error.FailedToSetSocketFlags;
            break :init Self{ .socket = .{ .handle = socket } };
        },
        .display => |display| init: {
            const is_absolute = std.fs.path.isAbsolute(display);
            var un_addr = std.posix.sockaddr.un{ .path = undefined };
            @memset(&un_addr.path, 0);
            if (is_absolute) {
                @memcpy(&un_addr.path, display);
            } else {
                const xdg_runtime_dir = std.posix.getenv("XDG_RUNTIME_DIR") orelse
                    return error.NoXdgRuntimeDir;
                _ = std.fmt.bufPrint(&un_addr.path, "{s}/{s}", .{ xdg_runtime_dir, display }) catch
                    return error.DisplayPathTooLong;
            }
            const socket = std.posix.socket(
                std.posix.AF.UNIX,
                std.posix.SOCK.STREAM | std.posix.SOCK.NONBLOCK,
                0,
            ) catch return error.FailedToCreateSocket;
            const addr = std.net.Address{ .un = un_addr };
            std.posix.connect(socket, &addr.any, @sizeOf(@TypeOf(un_addr))) catch
                return error.FailedToConnectToSocket;
            break :init Self{ .socket = .{ .handle = socket } };
        },
    };
}

pub fn deinit(self: Self) void {
    self.socket.close();
}
