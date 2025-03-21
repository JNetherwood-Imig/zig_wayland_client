const std = @import("std");

const Protocol = @import("elements.zig").Protocol;

const Self = @This();

allocator: std.mem.Allocator,
buf: []const u8,
index: usize,

pub fn init(allocator: std.mem.Allocator, file: std.fs.File) !Self {
    return .{
        .allocator = allocator,
        .buf = try file.readToEndAlloc(allocator, 1024 * 1024),
        .index = 0,
    };
}

pub fn getNextElementName(self: *Self) ?[]const u8 {
    while (self.buf[self.index] != '<') {
        self.index += 1;
        if (self.index == self.buf.len) return null;
    }
    self.index += 1;
    const rel_idx = blk: {
        const end = std.mem.indexOfScalar(u8, self.buf[self.index..], '>').?;
        break :blk @min(std.mem.indexOfScalar(u8, self.buf[self.index..], ' ') orelse end, end);
    };
    const elem = self.buf[self.index .. self.index + rel_idx];
    self.index += rel_idx;
    return if (std.mem.eql(u8, elem, "?xml") or std.mem.eql(u8, elem, "!--"))
        self.getNextElementName()
    else
        elem;
}

pub fn getNextAttributeName(self: *Self) ?[]const u8 {
    if (self.buf[self.index] == '"') self.index += 1;
    self.consumeWhitespace();
    const rel_idx = blk: {
        const equals = std.mem.indexOfScalar(u8, self.buf[self.index..], '=') orelse return null;
        if (std.mem.indexOfScalar(u8, self.buf[self.index..], '>').? < equals) return null;
        break :blk equals;
    };
    defer self.index += rel_idx;
    return self.buf[self.index .. self.index + rel_idx];
}

pub fn getNextAttributeValue(self: *Self) ?[]const u8 {
    self.index += std.mem.indexOfScalar(u8, self.buf[self.index..], '"').? + 1;
    const rel_idx = std.mem.indexOfScalar(
        u8,
        self.buf[self.index..],
        '"',
    ) orelse return null;
    defer self.index += rel_idx;
    return self.buf[self.index .. self.index + rel_idx];
}

pub fn getNextText(self: *Self) ?[]const u8 {
    const rel_start_idx = (std.mem.indexOfScalar(
        u8,
        self.buf[self.index..],
        '>',
    ) orelse return null) + 1;
    const rel_end_idx = std.mem.indexOfScalar(
        u8,
        self.buf[self.index + rel_start_idx ..],
        '<',
    ) orelse return null;
    defer self.index += rel_end_idx;
    return self.buf[self.index + rel_start_idx .. self.index + rel_end_idx];
}

pub fn isSelfClosingElement(self: *Self) bool {
    return (std.mem.indexOf(u8, self.buf[self.index..], "/>") orelse return false) <
        std.mem.indexOfScalar(u8, self.buf[self.index..], '<').?;
}

fn consumeWhitespace(self: *Self) void {
    while (self.buf[self.index] == ' ' or
        self.buf[self.index] == '\t' or
        self.buf[self.index] == '\n') self.index += 1;
}
