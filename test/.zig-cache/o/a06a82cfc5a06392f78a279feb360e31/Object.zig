const std = @import("std");
const Self = @This();
const Display = @import("Display.zig");
const Fixed = @import("Fixed.zig");

id: u32,
display: *Display,
event0_index: u32,

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
        .event0_index = T.event0_index,
    };
    try self.sendRequest(new_proxy.id, opcode, args);
    return T{ .proxy = new_proxy };
}

pub fn sendDestroyRequest(self: Self, opcode: u32, args: anytype) void {
    self.sendRequest(null, opcode, args) catch return;
}

pub fn sendRequest(self: Self, new_id: ?u32, opcode: u32, args: anytype) !void {
    const type_info = comptime @typeInfo(@TypeOf(args));
    comptime switch (type_info) {
        .@"struct" => |s| {
            if (!s.is_tuple) @compileError("expected args to be a tuple");
        },
        else => @compileError("expected args to be a tuple"),
    };

    const message_size = comptime calculateMessageSize(args);
    const buf = try self.display.allocator.alloc(u8, message_size);
    defer self.display.allocator.free(buf);
    const head = MessageHeader{ .object = self.id, .opcode = @intCast(opcode), .len = @intCast(message_size) };
    @as(*MessageHeader, @ptrCast(@alignCast(&buf[0]))).* = head;

    var index: usize = 8;
    inline for (type_info.@"struct".fields) |field| {
        const arg: Arg = @field(args, field.name);
        index += arg.print(buf[index..], new_id);
    }

    try std.posix.write(self.display.sockfd, buf);
}

fn calculateMessageSize(args: anytype) usize {
    comptime var size: usize = 8;
    inline for (@typeInfo(@TypeOf(args)).@"struct".fields) |field| {
        switch (@as(Arg, @field(args, field.name))) {
            .int, .uint, .object, .fixed => size += 4,
            .new_id => |id| {
                size += 4;
                if (id.interface) |i| size += roundup4(@intCast(i.len + 1)) + 8;
            },
            .string => |str| size += roundup4(@intCast(str.len + 1)) + 4,
            .array => |arr| size += roundup4(@intCast(arr.len)),
            .fd => {},
        }
    }
}
