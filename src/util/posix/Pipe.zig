handle: [2]File,

pub const CreateError = error{
    ProcessFdLimitReached,
    SystemFdLimitReached,
};

pub fn create() CreateError!Self {
    var fds = [2]Fd{ undefined, undefined };
    const ret = system.pipe(&fds);
    return switch (Errno.get(ret)) {
        .success => Self{ .handle = [_]File{
            File{ .handle = fds[0] },
            File{ .handle = fds[1] },
        } },
        .too_many_open_files => error.ProcessFdLimitReached,
        .too_many_open_files_in_system => error.SystemFdLimitReached,
        else => unreachable,
    };
}

pub fn close(self: Self) void {
    for (self.handle) |file| file.close();
}

pub fn getReadFile(self: Self) File {
    return self.handle[0];
}

pub fn getWriteFile(self: Self) File {
    return self.handle[1];
}

const Self = @This();
const std = @import("std");
const system = std.os.linux;
const Errno = @import("errno.zig").Errno;
const File = @import("File.zig");
const Fd = File.Fd;
const io = @import("../io.zig");
