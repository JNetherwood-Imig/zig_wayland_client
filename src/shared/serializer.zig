const std = @import("std");
const s = @import("serializer_utils.zig");
const Socket = @import("Socket.zig");
const Header = s.Header;

threadlocal var message: packed struct {
    header: Header,
    scratch_buf: [std.math.maxInt(u16) + 8]u8,
} = undefined;
threadlocal var buf = undefined;

pub fn sendMessage(socket: Socket, object: u32, opcode: usize, args: anytype) !void {
    message.header = .{ .object = object, .opcode = opcode, .length = 8 };
    buf = &message.scratch_buf;

    try socket.sendWithFds(fds, std.mem.asBytes(&message));
}
