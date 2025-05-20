id: u32,
event0_index: usize,

pub fn marshalCreateArgs(
    self: Proxy,
    comptime T: type,
    comptime fd_count: usize,
    new_proxy: Proxy,
    opcode: u32,
    args: anytype,
) !T {
    try self.marshalArgs(fd_count, opcode, args);
    return T{
        .proxy = new_proxy,
    };
}

pub fn marshalDestroyArgs(self: Proxy, comptime fd_count: usize, opcode: usize, args: anytype) void {
    self.marshalArgs(fd_count, opcode, args) catch {};
}

pub fn marshalArgs(self: Proxy, comptime fd_count: usize, opcode: usize, args: anytype) !void {
    var fds: [fd_count]os.File = undefined;
    var buf align(4) = [_]u8{0} ** 65535;

    var s = Serializer.init(&buf, &fds);
    s.writeAll(self.id, opcode, args);
    const len = s.length;

    const sent = try manager.socket.sendMessage(
        [fd_count]os.File,
        fds,
        .rights,
        buf[0..len],
        .{},
    );

    if (sent < buf.len) try self.socket.writeAll(buf[sent..len]);
}

const Proxy = @This();

const std = @import("std");
const os = @import("os");
const manager = @import("proxy_manager.zig");
const Fixed = @import("Fixed.zig");
const Serializer = @import("Serializer.zig");
const Allocator = std.mem.Allocator;
const File = os.File;
