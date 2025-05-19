const std = @import("std");
const Parser = @import("Parser.zig");
const Description = @import("Description.zig");
const c = @import("common.zig");
const Self = @This();

name: []const u8,
since: ?[]const u8 = null,
bitfield: ?[]const u8 = null,
description: ?Description = null,
entries: std.ArrayList(Entry),
type_name: []const u8,
numeric_since: ?u32 = null,
is_bitfield: bool = false,
allocator: std.mem.Allocator,

const ExampleEnum = enum(u32) {
    value_one = 1,
    value_two = 2,
    value_three = 3,
};

const ExampleBitfield = packed struct(u32) {
    option_one: bool = false,
    option_two: bool = false,
    option_three: bool = false,
    _: u29 = 0,
};

pub fn init(allocator: std.mem.Allocator, parser: *Parser) !Self {
    var self = Self{
        .name = undefined,
        .entries = std.ArrayList(Entry).init(allocator),
        .type_name = undefined,
        .allocator = allocator,
    };

    while (parser.getNextAttributeName()) |attrib| {
        if (std.mem.eql(u8, attrib, "name")) {
            self.name = parser.getNextAttributeValue().?;
            self.type_name = try c.snakeToPascal(self.allocator, self.name);
            continue;
        }
        if (std.mem.eql(u8, attrib, "since")) {
            self.since = parser.getNextAttributeValue().?;
            continue;
        }
        if (std.mem.eql(u8, attrib, "bitfield")) {
            self.bitfield = parser.getNextAttributeValue().?;
            self.is_bitfield = std.mem.eql(u8, self.bitfield.?, "true");
            continue;
        }

        unreachable;
    }

    while (parser.getNextElementName()) |elem| {
        if (std.mem.eql(u8, elem, "/enum")) break;
        if (std.mem.eql(u8, elem, "description")) {
            self.description = Description.init(parser);
            continue;
        }
        if (std.mem.eql(u8, elem, "entry")) {
            try self.entries.append(try Entry.init(parser));
            continue;
        }

        unreachable;
    }

    return self;
}

pub fn deinit(self: Self) void {
    self.allocator.free(self.type_name);
    self.entries.deinit();
}

pub fn write(self: Self, writer: std.fs.File.Writer) !void {
    if (self.description) |description| try description.emit(writer, "\t///");
    if (self.is_bitfield) {
        try self.writeBitfield(writer);
    } else {
        try self.writeEnum(writer);
    }
}

pub fn writeEnum(self: Self, writer: std.fs.File.Writer) !void {
    try writer.print("\tpub const {s} = enum(u32) {{\n", .{self.type_name});
    for (self.entries.items) |entry| try entry.writeEnum(writer);
    try writer.print("\t}};\n", .{});
}

pub fn writeBitfield(self: Self, writer: std.fs.File.Writer) !void {
    try writer.print("\tpub const {s} = packed struct(u32) {{\n", .{self.type_name});
    for (self.entries.items) |entry| try entry.writeBitfield(writer);
    try writer.print("\t\t_: u{d} = 0,\n", .{32 - self.entries.items.len});
    try writer.writeAll("\t};\n");
}

const Entry = struct {
    name: []const u8,
    value: []const u8,
    summary: ?[]const u8 = null,
    since: ?[]const u8 = null,
    deprecated_since: ?[]const u8 = null,
    description: ?Description = null,
    numeric_since: ?u32 = null,
    numeric_deprecated_since: ?u32 = null,

    pub fn init(parser: *Parser) !Entry {
        var self = Entry{
            .name = undefined,
            .value = undefined,
        };

        while (parser.getNextAttributeName()) |attrib| {
            if (std.mem.eql(u8, attrib, "name")) {
                self.name = parser.getNextAttributeValue().?;
                continue;
            }
            if (std.mem.eql(u8, attrib, "value")) {
                self.value = parser.getNextAttributeValue().?;
                continue;
            }
            if (std.mem.eql(u8, attrib, "summary")) {
                self.summary = parser.getNextAttributeValue().?;
                continue;
            }
            if (std.mem.eql(u8, attrib, "since")) {
                self.since = parser.getNextAttributeValue().?;
                continue;
            }
            if (std.mem.eql(u8, attrib, "deprecated-since")) {
                self.deprecated_since = parser.getNextAttributeValue().?;
                continue;
            }

            unreachable;
        }

        if (!parser.isSelfClosingElement()) {
            _ = parser.getNextElementName().?;
            self.description = Description.init(parser);
            _ = parser.getNextElementName().?;
        }

        return self;
    }

    fn writeDescription(self: Entry, writer: std.fs.File.Writer) !void {
        if (self.description) |description| {
            try description.emit(writer, "\t\t///");
        } else if (self.summary) |summary| {
            var lines = std.mem.splitScalar(u8, summary, '\n');
            while (lines.next()) |line| {
                try writer.print("\t\t/// {s}\n", .{line});
            }
        }
    }

    pub fn writeEnum(self: Entry, writer: std.fs.File.Writer) !void {
        try self.writeDescription(writer);
        const invalid_name = !std.zig.isValidId(self.name);
        try writer.print("\t\t{s}{s}{s} = {s},\n", .{
            if (invalid_name) "@\"" else "",
            self.name,
            if (invalid_name) "\"" else "",
            self.value,
        });
    }

    pub fn writeBitfield(self: Entry, writer: std.fs.File.Writer) !void {
        try self.writeDescription(writer);
        const invalid_name = !std.zig.isValidId(self.name);
        try writer.print("\t\t{s}{s}{s}:bool = false,\n", .{
            if (invalid_name) "@\"" else "",
            self.name,
            if (invalid_name) "\"" else "",
        });
    }
};
