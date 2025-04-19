const std = @import("std");
const system = std.os.linux;
const io = @import("io.zig");

pub const Errno = @import("posix/errno.zig").Errno;
pub const File = @import("posix/file.zig").File;
pub const Epoll = @import("posix/Epoll.zig");
pub const Pipe = @import("posix/Pipe.zig");
pub const Socket = @import("posix/Socket.zig");
pub usingnamespace @import("posix/poll.zig");
pub usingnamespace @import("posix/signal.zig");
