const std = @import("std");
const Parser = @import("Parser.zig");
const Description = @import("Description.zig");
const Arg = @import("Arg.zig");
const Interface = @import("Interface.zig");
const c = @import("common.zig");
const Self = @This();

name: []const u8,
type: ?[]const u8 = null,
since: ?[]const u8 = null,
deprecated_since: ?[]const u8 = null,
description: ?Description = null,
args: std.ArrayList(Arg),
type_name: []const u8,
numeric_since: ?u32 = null,
numeric_deprecated_since: ?u32 = null,
fd_count: usize = 0,
allocator: std.mem.Allocator,
interface: Interface,

pub fn init(allocator: std.mem.Allocator, parser: *Parser, interface: Interface) !Self {
    var self = Self{
        .name = undefined,
        .args = std.ArrayList(Arg).init(allocator),
        .type_name = undefined,
        .allocator = allocator,
        .interface = interface,
    };

    while (parser.getNextAttributeName()) |attrib| {
        if (std.mem.eql(u8, attrib, "name")) {
            self.name = parser.getNextAttributeValue().?;
            self.type_name = try c.snakeToPascal(allocator, self.name);
            continue;
        }
        if (std.mem.eql(u8, attrib, "type")) {
            self.type = parser.getNextAttributeValue().?;
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

    while (parser.getNextElementName()) |elem| {
        if (std.mem.eql(u8, elem, "/event")) break;
        if (std.mem.eql(u8, elem, "description")) {
            self.description = Description.init(parser);
            continue;
        }
        if (std.mem.eql(u8, elem, "arg")) {
            const arg = try Arg.init(self.allocator, parser);
            if (arg.enumerated_type == .fd) self.fd_count += 1;
            try self.args.append(arg);
            continue;
        }

        unreachable;
    }

    return self;
}

pub fn deinit(self: Self) void {
    self.allocator.free(self.type_name);
    for (self.args.items) |arg| arg.deinit();
    self.args.deinit();
}

pub fn write(self: Self, writer: std.fs.File.Writer) !void {
    if (self.description) |description| try description.emit(writer, "\t///");
    try writer.print("\tpub const {s}Event = struct {{\n", .{self.type_name});
    try writer.print("\t\tself: *const {s},\n", .{self.interface.type_name});
    for (self.args.items) |arg| try arg.write(writer);
    try writer.print("\t}};\n", .{});
}
