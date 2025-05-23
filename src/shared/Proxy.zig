const std = @import("std");
const os = @import("os");
const m = @import("message_utils.zig");
const roundup4 = m.roundup4;
const Fixed = @import("Fixed.zig");
const ProxyManager = @import("ProxyManager.zig");
const Allocator = std.mem.Allocator;
const GenericNewId = m.GenericNewId;
const Array = m.Array;
const String = m.String;
const Header = m.Header;

const Proxy = @This();

gpa: Allocator,
id: u32,
event0_index: usize,
manager: *ProxyManager,

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

pub fn marshalDestroyArgs(self: Proxy, comptime fd_count: usize, opcode: u32, args: anytype) void {
    self.marshalArgs(fd_count, opcode, args) catch {};
}

pub fn marshalArgs(self: Proxy, comptime fd_count: usize, opcode: u32, args: anytype) !void {
    var fds: [fd_count]os.File = undefined;
    const len = calculateArgsLen(args) + @sizeOf(Header);
    const buf = try self.gpa.alloc(u8, len);
    defer self.gpa.free(buf);

    const head = Header{
        .object = self.id,
        .opcode = @intCast(opcode),
        .length = @intCast(len),
    };
    @as(*Header, @ptrCast(@alignCast(&buf[0]))).* = head;

    serializeArgs(buf[@sizeOf(Header)..], &fds, args);

    const sent = try self.socket.sendMessage([fd_count]os.File, fds, .rights, buf, .{});
    if (sent < buf.len) try self.socket.writeAll(buf[sent..]);
}

fn calculateArgsLen(args: anytype) usize {
    var len: usize = 0;
    inline for (@typeInfo(@TypeOf(args)).@"struct".fields) |field_info| {
        const field = @field(args, field_info.name);
        len += switch (field_info.type) {
            i32, u32, Fixed => 4,
            String => 4 + roundup4(field.len + 1),
            GenericNewId => 12 + roundup4(field.interface.len + 1),
            Array => 4 + roundup4(field.len),
            os.File => 0,
            else => switch (@typeInfo(field_info.type)) {
                .@"enum", .@"struct", .optional => 4,
                else => std.debug.panic("Unexpected arg type: {s}", .{@typeName(field_info.type)}),
            },
        };
    }
    return len;
}

test "calculateArgsLen" {
    const int: i32 = 4;
    const uint: u32 = 1245;
    const fixed = Fixed.from(f64, 15.0);
    const string1: String = "hello";
    const string2: String = "Hello, world!";
    const new_id = GenericNewId{ .interface = "wl_compositor", .version = 6, .id = 3 };
    const array: Array = &([_]u8{1} ** 13);
    try std.testing.expectEqual(@as(usize, 0), calculateArgsLen(.{}));
    try std.testing.expectEqual(@as(usize, 4), calculateArgsLen(.{uint}));
    try std.testing.expectEqual(@as(usize, 12), calculateArgsLen(.{ int, uint, fixed }));
    try std.testing.expectEqual(@as(usize, 28), calculateArgsLen(.{ string2, fixed, fixed }));
    try std.testing.expectEqual(@as(usize, 40), calculateArgsLen(.{ string1, new_id }));
    try std.testing.expectEqual(@as(usize, 36), calculateArgsLen(.{ array, string1, uint }));
}

fn serializeInt(buf: []u8, int: i32) []u8 {
    @as(*i32, @ptrCast(@alignCast(&buf[0]))).* = int;
    return buf[4..];
}

test "serializeInt" {
    var buf = [_]u8{0} ** 8;
    var slice: []u8 = &buf;
    slice = serializeInt(slice, 4);
    slice = serializeInt(slice, 12);
    try std.testing.expectEqual([_]u8{ 4, 0, 0, 0, 12, 0, 0, 0 }, buf);
    var buf2 = [_]u8{0} ** 4;
    _ = serializeInt(&buf2, -128821);
    try std.testing.expectEqual(std.mem.toBytes(@as(i32, -128821)), buf2);
}

fn serializeUint(buf: []u8, uint: u32) []u8 {
    @as(*u32, @ptrCast(@alignCast(&buf[0]))).* = uint;
    return buf[4..];
}

test "serializeUint" {
    var buf = [_]u8{0} ** 4;
    _ = serializeUint(&buf, 327854);
    try std.testing.expectEqual(std.mem.toBytes(@as(u32, 327854)), buf);
}

fn serializeString(buf: []u8, string: String) []u8 {
    const len: u32 = @intCast(string.len + 1);
    var write_buf = serializeUint(buf, len);
    const padded_len = roundup4(len);
    @memcpy(write_buf[0..string.len], string);
    write_buf[string.len] = 0;
    return write_buf[padded_len..];
}

test "serializeString" {
    const str: [:0]const u8 = "Hello, world!";
    const expected = [_]u8{ 14, 0, 0, 0 } ++
        [_]u8{ 'H', 'e', 'l', 'l', 'o', ',', ' ', 'w', 'o', 'r', 'l', 'd', '!', 0, 0, 0 };
    var buf = [_]u8{0} ** 20;
    _ = serializeString(&buf, str);
    try std.testing.expectEqual(expected, buf);
}

fn serializeNewId(buf: []u8, new_id: GenericNewId) []u8 {
    var write_buf = serializeString(buf, new_id.interface);
    write_buf = serializeUint(write_buf, new_id.version);
    return serializeUint(write_buf, new_id.id);
}

test "serializeNewId" {
    const new_id = GenericNewId{
        .interface = "wl_compositor",
        .version = 6,
        .id = 3,
    };
    const expected = [_]u8{ 14, 0, 0, 0 } ++
        [_]u8{ 'w', 'l', '_', 'c', 'o', 'm', 'p', 'o', 's', 'i', 't', 'o', 'r', 0, 0, 0 } ++
        [_]u8{ 6, 0, 0, 0, 3, 0, 0, 0 };
    var buf = [_]u8{0} ** 28;
    _ = serializeNewId(&buf, new_id);
    try std.testing.expectEqual(expected, buf);
}

fn serializeArray(buf: []u8, array: Array) []u8 {
    const len: u32 = @intCast(array.len);
    var write_buf = serializeUint(buf, len);
    const padded_len = roundup4(len);
    @memcpy(write_buf[0..array.len], array);
    return write_buf[padded_len..];
}

test "serializeArray" {
    const arr = [_]u32{ 4, 1, 3, 6 };
    const bytes = std.mem.toBytes(arr);
    const expected = [_]u8{ 16, 0, 0, 0, 4, 0, 0, 0, 1, 0, 0, 0, 3, 0, 0, 0, 6, 0, 0, 0 };
    var buf = [_]u8{0} ** 20;
    _ = serializeArray(&buf, &bytes);
    try std.testing.expectEqual(buf, expected);
}

fn serializeFd(fds: []os.File, fd: os.File) []os.File {
    fds[0] = fd;
    return fds[1..];
}

fn serializeArgs(buf: []u8, fds: []os.File, args: anytype) void {
    var write_buf = buf;
    var write_fds = fds;
    inline for (@typeInfo(@TypeOf(args)).@"struct".fields) |field_info| {
        const field = @field(args, field_info.name);
        switch (field_info.type) {
            i32 => write_buf = serializeInt(write_buf, field),
            u32 => write_buf = serializeUint(write_buf, field),
            Fixed => write_buf = serializeInt(write_buf, field.data),
            String => write_buf = serializeString(write_buf, field),
            GenericNewId => write_buf = serializeNewId(write_buf, field),
            Array => write_buf = serializeArray(write_buf, field),
            os.File => {
                write_fds = serializeFd(write_fds, field);
            },
            else => switch (@typeInfo(field_info.type)) {
                .@"enum" => write_buf = serializeUint(write_buf, @intFromEnum(field)),
                .@"struct" => |s| { // Bitfield
                    if (s.layout == .@"packed") {
                        comptime std.debug.assert(s.backing_integer.? == u32);
                        write_buf = serializeUint(write_buf, @bitCast(field));
                    } else { // Object
                        comptime std.debug.assert(@hasField(field_info.type, "proxy"));
                        write_buf = serializeUint(write_buf, field.proxy.id);
                    }
                },
                .optional => {
                    const id = id: {
                        if (field) |f| break :id f.proxy.id;
                        break :id 0;
                    };
                    write_buf = serializeUint(write_buf, id);
                },
                else => unreachable,
            },
        }
    }
}

test "serializeArgs" {
    const args = .{
        @as(u32, 1),
        GenericNewId{
            .interface = "wl_compositor",
            .version = 6,
            .id = 3,
        },
    };
    const expected = [_]u8{ 1, 0, 0, 0, 14, 0, 0, 0 } ++
        [_]u8{ 'w', 'l', '_', 'c', 'o', 'm', 'p', 'o', 's', 'i', 't', 'o', 'r', 0, 0, 0 } ++
        [_]u8{ 6, 0, 0, 0, 3, 0, 0, 0 };

    var buf = [_]u8{0} ** 32;
    _ = serializeArgs(&buf, &.{}, args);

    try std.testing.expectEqual(buf, expected);
}
