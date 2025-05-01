id: u32,
event0_index: usize,
socket: os.File,
id_allocator: *IdAllocator,
object_list: *std.ArrayList(Proxy),
gpa: Allocator,

pub fn marshalCreateArgs(
    self: Proxy,
    comptime T: type,
    comptime fd_count: usize,
    new_id: u32,
    opcode: u32,
    args: anytype,
) !T {
    try self.marshalArgs(fd_count, opcode, args);
    const proxy = Proxy{
        .socket = self.socket,
        .event0_index = T.event0_index,
        .id = new_id,
        .id_allocator = self.id_allocator,
        .object_list = self.object_list,
        .gpa = self.gpa,
    };
    try self.object_list.append(proxy);
    return T{
        .proxy = proxy,
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

const wl = struct {
    const EventType = enum(u32) {
        none,
    };

    const Event = union(EventType) {
        none: void,
    };
};

pub fn parseEvent(self: Proxy, header: Header) wl.Event {
    const tag_name = @tagName(@as(wl.EventType, @enumFromInt(self.event0_index + header.opcode)));
    const union_field_info = inline for (@typeInfo(wl.Event).@"union".fields) |field| {
        if (std.mem.eql(u8, field.name, tag_name)) {
            break field;
        }
    } else unreachable;
    const struct_type = union_field_info.type;
    var struct_value = struct_type{ .self = .{ .proxy = self } };

    const fd_count = count: {
        comptime var count: usize = 0;
        inline for (@typeInfo(struct_type).@"struct".fields) |field| {
            if (@TypeOf(field) == os.File) count += 1;
        }
        break :count count;
    };

    const buf = try self.gpa.alloc(u8, header.length - @sizeOf(Header));
    defer self.gpa.free(buf);

    var fds: [fd_count]os.File = undefined;
    _ = try self.socket.recieveMessage(@TypeOf(fds), &fds, buf, 0);

    var index: usize = 0;
    var fd_idx: usize = 0;

    inline for (@typeInfo(struct_type).@"struct".fields) |field| {
        if (comptime std.mem.eql(u8, field.name, "self")) continue;
        switch (field.type) {
            u32 => {
                @field(struct_value, field.name) = std.mem.bytesToValue(u32, buf[index .. index + 4]);
                index += 4;
            },
            i32 => {
                @field(struct_value, field.name) = std.mem.bytesToValue(i32, buf[index .. index + 4]);
                index += 4;
            },
            Array => {
                const len = std.mem.bytesToValue(u32, buf[index .. index + 4]);
                index += 4;
                const rounded_len = roundup4(len);
                @field(struct_value, field.name) = try self.gpa.dupe(u8, buf[index .. index + len]);
                index += rounded_len;
            },
            String => {
                const len = std.mem.bytesToValue(u32, buf[index .. index + 4]);
                index += 4;
                const rounded_len = roundup4(len);
                @field(struct_value, field.name) = try self.gpa.dupeZ(u8, buf[index .. index + len - 1]);
                index += rounded_len;
            },
            os.File => {
                @field(struct_value, field.name) = fds[fd_idx];
                fd_idx += 1;
            },
            else => std.debug.panic("Unexpected type: {s}", .{@typeName(field.type)}),
        }
    }
    return @unionInit(wl.Event, union_field_info.name, struct_value);
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
            else => unreachable,
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
            else => unreachable,
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

const Proxy = @This();

const std = @import("std");
const os = @import("../os.zig");
const m = @import("../common/message_utils.zig");
const Fixed = @import("../common/Fixed.zig");
const IdAllocator = @import("../common/IdAllocator.zig");
const roundup4 = m.roundup4;
const Allocator = std.mem.Allocator;
const GenericNewId = m.GenericNewId;
const Array = m.Array;
const String = m.String;
const Header = m.Header;
