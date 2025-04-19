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

test "file" {
    io.eprintln("Testing file functions...");

    comptime std.debug.assert(@sizeOf(File) == @sizeOf(std.posix.fd_t));

    const fd = try File.open("/dev/dri/card1", .{}, .{});
    defer fd.close();

    io.eprintlnf("GPU fd is {any}", .{fd});

    var flags = try fd.getFlags();
    io.eprintlnf("Old GPU fd flags are {any}", .{flags});
    flags.cloexec = true;
    try fd.setFlags(flags);
    io.eprintlnf("New GPU fd flags are {any}", .{flags});
}

test "epoll" {
    io.eprintln("Testing epoll...");
    const fd = try File.open("/dev/dri/card1", .{}, .{});
    defer fd.close();

    const epoll = try Epoll.create(.{});
    defer epoll.close();

    try epoll.add(fd, .{
        .events = .{ .in = true },
        .data = .{ .fd = fd },
    });
    try epoll.mod(fd, .{
        .events = .{ .out = true },
        .data = .{ .fd = fd },
    });

    var events = [1]Epoll.Event{undefined};
    const count = try epoll.wait(&events, 10);
    io.eprintlnf("Got {d} events", .{count});

    try epoll.del(fd);
}

test "pipe" {
    io.eprintln("Testing pipe...");
    const pipe = try Pipe.create();
    defer pipe.close();

    const read = pipe.getReadFile();
    const write = pipe.getWriteFile();

    io.eprintlnf(
        "Pipe read file is {any} and write file is {any}",
        .{ read, write },
    );
}
