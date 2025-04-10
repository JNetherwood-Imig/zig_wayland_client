const std = @import("std");
const Parser = @import("Parser.zig");
const Description = @import("Description.zig");
const c = @import("common.zig");
const Self = @This();

name: []const u8,
type: []const u8,
summary: ?[]const u8 = null,
interface: ?[]const u8 = null,
allow_null: ?[]const u8 = null,
@"enum": ?[]const u8 = null,
description: ?Description = null,
enumerated_type: enum {
    int,
    uint,
    fixed,
    string,
    object,
    new_id,
    array,
    fd,
},
interface_type: ?[]const u8 = null,
nullable: bool = false,
enum_type: ?[]const u8 = null,
final_name: ?[]const u8 = null,
allocator: std.mem.Allocator,

pub fn init(allocator: std.mem.Allocator, parser: *Parser) !Self {
    var self = Self{
        .name = undefined,
        .type = undefined,
        .enumerated_type = undefined,
        .allocator = allocator,
    };

    while (parser.getNextAttributeName()) |attrib| {
        if (std.mem.eql(u8, attrib, "name")) {
            self.name = parser.getNextAttributeValue().?;
            continue;
        }
        if (std.mem.eql(u8, attrib, "type")) {
            self.type = parser.getNextAttributeValue().?;
            if (std.mem.eql(u8, self.type, "int")) {
                self.enumerated_type = .int;
            } else if (std.mem.eql(u8, self.type, "uint")) {
                self.enumerated_type = .uint;
            } else if (std.mem.eql(u8, self.type, "object")) {
                self.enumerated_type = .object;
            } else if (std.mem.eql(u8, self.type, "fixed")) {
                self.enumerated_type = .fixed;
            } else if (std.mem.eql(u8, self.type, "new_id")) {
                self.enumerated_type = .new_id;
            } else if (std.mem.eql(u8, self.type, "array")) {
                self.enumerated_type = .array;
            } else if (std.mem.eql(u8, self.type, "string")) {
                self.enumerated_type = .string;
            } else if (std.mem.eql(u8, self.type, "fd")) {
                self.enumerated_type = .fd;
            } else {
                unreachable;
            }

            continue;
        }
        if (std.mem.eql(u8, attrib, "summary")) {
            self.summary = parser.getNextAttributeValue().?;
            continue;
        }
        if (std.mem.eql(u8, attrib, "interface")) {
            self.interface = parser.getNextAttributeValue().?;
            self.interface_type = try c.snakeToPascal(self.allocator, std.mem.trimLeft(u8, self.interface.?, "wl_"));
            continue;
        }
        if (std.mem.eql(u8, attrib, "allow-null")) {
            self.allow_null = parser.getNextAttributeValue().?;
            self.nullable = std.mem.eql(u8, self.allow_null.?, "true");
            continue;
        }
        if (std.mem.eql(u8, attrib, "enum")) {
            self.@"enum" = parser.getNextAttributeValue().?;
            self.enum_type = try c.snakeToPascal(self.allocator, std.mem.trimLeft(u8, self.@"enum".?, "wl_"));
            continue;
        }

        unreachable;
    }

    if (!parser.isSelfClosingElement()) {
        self.description = Description.init(parser);
        _ = parser.getNextElementName().?;
    }

    return self;
}

pub fn deinit(self: Self) void {
    if (self.final_name) |final_name| self.allocator.free(final_name);
    if (self.interface_type) |interface_type| self.allocator.free(interface_type);
    if (self.enum_type) |enum_type| self.allocator.free(enum_type);
}

pub fn write(self: Self, writer: std.fs.File.Writer) !void {
    const type_str = self.enum_type orelse switch (self.enumerated_type) {
        .int => "i32",
        .uint => "u32",
        .object => self.interface_type orelse "u32",
        .fd => "std.posix.fd_t", // Maybe this should be an i32 to avoid importing std?
        .array => "*anyopaque", // Should this be a slice or anytype?
        .string => "[]const u8",
        .fixed => "i32", // TODO implement fixed type with conversion utils
        .new_id => self.interface_type orelse "u32",
    };
    if (self.description) |description| {
        try description.emit(writer, "\t\t///");
    } else if (self.summary) |summary| try writer.print("\t\t/// {s}\n", .{summary});
    try writer.print("\t\t{s}: {s}{s},\n", .{
        self.final_name orelse self.name,
        if (self.nullable) "?" else "",
        type_str,
    });
}
