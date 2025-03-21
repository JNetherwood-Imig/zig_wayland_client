const std = @import("std");
const Self = @This();
const Display = @import("Display.zig");
const Fixed = @import("Fixed.zig");

id: u32,
display: *Display,

pub const Arg = union(enum) {
    int: i32,
    uint: u32,
    fixed: Fixed,
    string: []const u8,
    object: u32,
    new_id: struct {
        interface: ?[]const u8 = null,
        version: ?u32 = null,
    },
    array: []const u8,
    fd: i32,

    pub fn print(self: Arg, buf: []u8, new_id: ?u32) usize {
        switch (self) {
            .int => |int| {
                @as(*i32, @ptrCast(@alignCast(&buf[0]))).* = int;
                return 4;
            },
            .uint, .object => |uint| {
                @as(*u32, @ptrCast(@alignCast(&buf[0]))).* = uint;
                return 4;
            },
            .fixed => |fix| {
                @as(*i32, @ptrCast(@alignCast(&buf[0]))).* = fix.data;
                return 4;
            },
            .string => |str| {
                @as(*u32, @ptrCast(@alignCast(&buf[0]))).* = @intCast(str.len + 1);
                @memcpy(buf[4..], str);
                return roundup4(@intCast(str.len + 1)) + 4;
            },
            .array => |arr| {
                @as(*u32, @ptrCast(@alignCast(&buf[0]))).* = @intCast(arr.len);
                @memcpy(buf[4..], arr);
                return roundup4(@intCast(arr.len)) + 4;
            },
            .new_id => |id| {
                var size: u32 = 0;
                if (id.interface) |ifce| {
                    @as(*u32, @ptrCast(@alignCast(&buf[0]))).* = @intCast(ifce.len + 1);
                    size += 4;
                    @memcpy(buf[size .. size + ifce.len], ifce);
                    size += roundup4(@intCast(ifce.len + 1));
                    @as(*u32, @ptrCast(@alignCast(&buf[size]))).* = id.version.?;
                    size += 4;
                }
                @as(*u32, @ptrCast(@alignCast(&buf[size]))).* = new_id.?;
                return size + 4;
            },
            .fd => {
                std.log.warn("Fd marshalling is not implemented", .{});
                return 0;
            },
        }
    }
};

inline fn roundup4(val: u32) u32 {
    return (val + 3) & ~@as(u32, 3);
}

const MessageHeader = packed struct(u64) {
    object: u32,
    opcode: u16,
    len: u16,
};

pub fn sendCreateRequest(self: Self, comptime T: type, display: *Display, opcode: u32, args: anytype) !T {
    const new_proxy = Self{
        .id = self.display.allocateId(),
        .display = display,
    };
    try self.sendRequest(new_proxy.id, opcode, args);
    return T{ .proxy = new_proxy };
}

pub fn sendDestroyRequest(self: Self, opcode: u32, args: anytype) void {
    std.debug.print("Destroying object {d}\n", .{self.id});
    self.sendRequest(null, opcode, args) catch return;
}

pub fn sendRequest(self: Self, new_id: ?u32, opcode: u32, args: anytype) !void {
    std.debug.print("Sending request {d} for object {d}\n", .{ opcode, self.id });
    const type_info = comptime @typeInfo(@TypeOf(args));
    comptime switch (type_info) {
        .@"struct" => |s| {
            if (!s.is_tuple) @compileError("expected args to be a tuple");
        },
        else => @compileError("expected args to be a tuple"),
    };

    var index: usize = 8;
    inline for (type_info.@"struct".fields) |field| {
        const arg: Arg = @field(args, field.name);
        index += arg.print(self.display.message_buf[index..], new_id);
    }

    const head = MessageHeader{ .object = self.id, .opcode = @intCast(opcode), .len = @intCast(index) };
    @as(*MessageHeader, @ptrCast(@alignCast(&self.display.message_buf[0]))).* = head;

    std.debug.print("{any}\n", .{self.display.message_buf[0..index]});

    // try self.display.sock.writeAll(self.display.message_buf[0..index]);
    std.debug.assert(try std.posix.write(self.display.sockfd, self.display.message_buf[0..index]) == index);
}
