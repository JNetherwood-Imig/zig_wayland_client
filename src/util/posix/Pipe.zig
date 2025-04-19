handle: [2]File,

pub const CreateError = error{
    ProcessFdLimitReached,
    SystemFdLimitReached,
};

pub fn create() CreateError!Self {
    var fds = [2]i32{ undefined, undefined };
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

pub fn read(self: Self, buf: []u8) std.fs.File.ReadError!usize {
    return try self.getReadFile().toStdFile().read(buf);
}

pub fn write(self: Self, buf: []const u8) std.fs.File.WriteError!usize {
    return try self.getWriteFile().toStdFile().write(buf);
}

pub fn writeAll(self: Self, buf: []const u8) std.fs.File.WriteError!void {
    try self.getWriteFile().toStdFile().writeAll(buf);
}

const Self = @This();
const std = @import("std");
const system = std.os.linux;
const Errno = @import("errno.zig").Errno;
const File = @import("file.zig").File;
const io = @import("../io.zig");
