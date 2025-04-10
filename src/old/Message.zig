const std = @import("std");
const Fixed = @import("Fixed.zig");

const Self = @This();

pub const Arg = union(enum) {
    int: i32,
    uint: u32,
    fixed: Fixed,
    string: [:0]const u8,
    object: u32,
    new_id: struct {
        interface: ?[]const u8 = null,
        version: ?u32 = null,
    },
    array: []const u8,
    fd: i32,
};

pub const Header = packed struct {
    pub const size = @sizeOf(Header);
    object: u32,
    opcode: u16,
    length: u16,
};

allocator: std.mem.Allocator,
head: Header,
buf: []u8,
ptr: [*]u8,
fd: ?i32 = null,

inline fn roundup4(val: anytype) @TypeOf(val) {
    comptime switch (@typeInfo(@TypeOf(val))) {
        .int => {},
        else => @compileError("Expected an integer type for roundup4"),
    };

    return (val + 3) & ~@as(@TypeOf(val), 3);
}

pub fn calculateSizeFromArgs(args: anytype) usize {
    _ = args;
    return 0;
}

pub fn init(allocator: std.mem.Allocator, object: u32, opcode: u32, args_size: usize) !Self {
    const head = Header{
        .object = object,
        .opcode = opcode,
        .length = args_size + Header.size,
    };
    const buf = try allocator.alloc(u8, head.length);
    @memcpy(buf, &head);
    return Self{
        .allocator = allocator,
        .head = head,
        .buf = buf,
        .ptr = buf.ptr + Header.size,
    };
}

pub fn deinit(self: Self) void {
    self.allocator.free(self.buf);
}

fn writeArg(self: *Self, arg: Arg) void {
    switch (arg) {
        .int => |int| {
            defer self.ptr += 4;
            @as(*i32, @ptrCast(@alignCast(self.ptr))).* = int;
        },
        .uint, .object => |uint| {
            defer self.ptr += 4;
            @as(*u32, @ptrCast(@alignCast(self.ptr))).* = uint;
        },
        .fixed => |fix| {
            defer self.ptr += 4;
            @as(*i32, @ptrCast(@alignCast(self.ptr))).* = fix.data;
        },
        .string => |str| {
            self.writeArg(.{ .uint = roundup4(str.len + 1) });
            @memcpy(self.ptr, str);
        },
        .array => |arr| {},
        else => unreachable,
    }
}

fn writeNewId(self: *Self, new_id: u32) void {}

fn writeNewIdGeneric(self: *Self, interface: []const u8, version: u32, new_id: u32) void {}

pub fn writeArgs(self: *Self, args: anytype) !void {}

pub fn readInt(self: *Self, comptime T: type) T {
    const info = @typeInfo(T).int;
    defer self.ptr += 4;
    return if (info.signedness == .signed)
        @intCast(@as(*i32, @ptrCast(@alignCast(self.ptr))).*)
    else
        @intCast(@as(*u32, @ptrCast(@alignCast(self.ptr))).*);
}

pub fn readArray(self: *Self, comptime T: type) []T {
    const len = self.readInt(usize);
    defer self.ptr += roundup4(len);
    return @ptrCast(self.ptr[0..len]);
}

pub fn readString(self: *Self) []const u8 {
    const len = self.readInt(usize);
    defer self.ptr += roundup4(len);
    return self.ptr[0 .. len - 1];
}
