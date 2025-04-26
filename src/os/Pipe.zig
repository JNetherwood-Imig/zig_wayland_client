handle: [2]File,

pub const CreateError = error{
    ProcessFdLimitReached,
    SystemFdLimitReached,
};

pub fn create() CreateError!Pipe {
    var fds = [2]i32{ undefined, undefined };
    const ret = system.pipe(&fds);
    return switch (errno(ret)) {
        .SUCCESS => Pipe{ .handle = [_]File{
            File{ .handle = fds[0] },
            File{ .handle = fds[1] },
        } },
        .MFILE => error.ProcessFdLimitReached,
        .NFILE => error.SystemFdLimitReached,
        else => unreachable,
    };
}

pub inline fn close(self: Pipe) void {
    for (self.handle) |file| file.close();
}

pub inline fn getReadFile(self: Pipe) File {
    return self.handle[0];
}

pub inline fn getWriteFile(self: Pipe) File {
    return self.handle[1];
}

pub inline fn read(self: Pipe, buf: []u8) File.ReadError!usize {
    return try self.getReadFile().read(buf);
}

pub inline fn write(self: Pipe, buf: []const u8) File.WriteError!usize {
    return try self.getWriteFile().write(buf);
}

pub inline fn writeAll(self: Pipe, buf: []const u8) File.WriteError!void {
    try self.getWriteFile().writeAll(buf);
}

const Pipe = @This();

const std = @import("std");
const system = std.os.linux;
const errno = std.posix.errno;
const File = @import("file.zig").File;
