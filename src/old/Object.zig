const std = @import("std");
const Self = @This();
const Display = @import("Display.zig");
const Fixed = @import("Fixed.zig");

id: u32,
display: *Display,
event0_index: u32 = 0,

inline fn roundup4(val: u32) u32 {
    return (val + 3) & ~@as(u32, 3);
}

pub fn sendCreateRequest(
    self: Self,
    comptime T: type,
    display: *Display,
    opcode: u32,
    args: anytype,
) !T {
    const new_proxy = Self{
        .id = self.display.allocateId(),
        .display = display,
        .event0_index = T.event0_index,
    };

    try self.sendRequest(new_proxy.id, opcode, args);
    try self.display.objects.append(new_proxy);
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

    const message_size = calculateMessageSize(args);
    const buf = try self.display.allocator.alloc(u8, message_size);
    defer self.display.allocator.free(buf);
    const head = MessageHeader{ .object = self.id, .opcode = @intCast(opcode), .length = @intCast(message_size) };
    @as(*MessageHeader, @ptrCast(@alignCast(&buf[0]))).* = head;

    var index: usize = 8;
    inline for (type_info.@"struct".fields) |field| {
        const arg: Arg = @field(args, field.name);
        index += arg.print(buf[index..], new_id);
    }

    _ = try std.posix.write(self.display.sockfd, buf);
}

fn calculateMessageSize(args: anytype) usize {
    var size: usize = 8;
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

    return size;
}
