head_ptr: *align(1) Header,
buf: []u8,
fd_buf: []File,
length: usize = 8,

pub fn init(buf: []u8, fd_buf: []File) Serializer {
    return Serializer{
        .head_ptr = std.mem.bytesAsValue(Header, buf[0..@sizeOf(Header)]),
        .buf = buf[@sizeOf(Header)..],
        .fd_buf = fd_buf,
    };
}

fn writeUint(self: *Serializer, val: u32) void {
    @as(*u32, @ptrCast(@alignCast(&self.buf[0]))).* = val;
    self.buf = self.buf[4..];
    self.length += 4;
}

fn writeInt(self: *Serializer, val: i32) void {
    @as(*i32, @ptrCast(@alignCast(&self.buf[0]))).* = val;
    self.buf = self.buf[4..];
    self.length += 4;
}

fn writeFixed(self: *Serializer, val: Fixed) void {
    self.writeInt(val.data);
}

fn writeString(self: *Serializer, str: String) void {
    const len = str.len + 1;
    self.writeUint(@intCast(len));
    @memcpy(self.buf[0..str.len], str);
    self.buf[str.len] = 0;
    const padded_len = roundup4(len);
    self.buf = self.buf[padded_len..];
    self.length += padded_len;
}

fn writeArray(self: *Serializer, arr: Array) void {
    self.writeUint(@intCast(arr.len));
    @memcpy(self.buf[0..arr.len], arr);
    const padded_len = roundup4(arr.len);
    self.buf = self.buf[padded_len..];
    self.length += padded_len;
}

fn writeNewId(self: *Serializer, id: GenericNewId) void {
    self.writeString(id.interface);
    self.writeUint(id.version);
    self.writeUint(id.id);
}

fn writeFd(self: *Serializer, fd: File) void {
    self.fd_buf[0] = fd;
    self.fd_buf = self.fd_buf[1..];
}

fn writeEnum(self: *Serializer, e: anytype) void {
    self.writeUint(@intFromEnum(e));
}

fn writeBitfield(self: *Serializer, bitfield: anytype) void {
    self.writeUint(@bitCast(bitfield));
}

fn writeObject(self: *Serializer, object: anytype) void {
    self.writeUint(object.proxy.id);
}

fn writeNullableObject(self: *Serializer, object: anytype) void {
    self.writeUint(if (object) |obj| obj.proxy.id else 0);
}

fn writeAny(self: *Serializer, arg: anytype) void {
    switch (@typeInfo(@TypeOf(arg))) {
        .@"enum" => self.writeEnum(arg),
        .@"struct" => |s| if (s.layout == .@"packed") self.writeBitfield(arg) else self.writeObject(arg),
        .optional => self.writeNullableObject(arg),
        else => unreachable,
    }
}

fn writeHeader(self: *Serializer, object: u32, opcode: usize) void {
    self.head_ptr.object = object;
    self.head_ptr.opcode = @intCast(opcode);
    self.head_ptr.length = @intCast(self.length);
}

pub fn writeAll(self: *Serializer, object: u32, opcode: usize, args: anytype) void {
    inline for (@typeInfo(@TypeOf(args)).@"struct".fields) |field_info| {
        const field = @field(args, field_info.name);
        switch (field_info.type) {
            i32 => self.writeInt(field),
            u32 => self.writeUint(field),
            File => self.writeFd(field),
            Fixed => self.writeFixed(field),
            Array => self.writeArray(field),
            String => self.writeString(field),
            GenericNewId => self.writeNewId(field),
            else => self.writeAny(field),
        }
    }
    self.writeHeader(object, opcode);
}

const Serializer = @This();

inline fn roundup4(val: usize) usize {
    return (val + 3) & ~@as(usize, 3);
}

const std = @import("std");
const Fixed = @import("Fixed.zig");
const os = @import("os");
const File = os.File;
const m = @import("message_utils.zig");
const String = m.String;
const Array = m.Array;
const Header = m.Header;
const GenericNewId = m.GenericNewId;
