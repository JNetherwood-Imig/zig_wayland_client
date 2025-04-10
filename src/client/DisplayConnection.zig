const std = @import("std");
const wl = @import("client_protocol");
const Connection = @import("Connection.zig");
const Self = @This();

display: wl.Display,
connection: Connection,

const Error = Connection.Error;

pub fn getConnectInfo() Connection.ConnectInfo {
    if (std.posix.getenv("WAYLAND_SOCKET")) |wayland_socket| {
        const socket = std.fmt.parseInt(std.posix.socket_t, wayland_socket, 10) catch null;
        if (socket) |sock| return .{ .socket = sock };
    }
    return .{ .display = std.posix.getenv("WAYLAND_DISPLAY") orelse "wayland-0" };
}

pub fn init(connect_info: anytype) Error!Self {
    const info: Connection.ConnectInfo = if (@TypeOf(connect_info) == Connection.ConnectInfo)
        connect_info
    else switch (@typeInfo(@TypeOf(connect_info))) {
        .comptime_int, .int => .{ .socket = @intCast(connect_info) },
        .pointer => |ptr| init: {
            _ = ptr;
            break :init .{ .display = @ptrCast(connect_info) };
        },
        .null => getConnectInfo(),
        else => @compileError("Invalid type"),
    };

    return Self{
        .display = undefined,
        .connection = try Connection.init(info),
    };
}

pub fn deinit(self: Self) void {
    self.connection.deinit();
}
