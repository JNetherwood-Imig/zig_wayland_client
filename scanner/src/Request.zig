const std = @import("std");
const Parser = @import("Parser.zig");
const Description = @import("Description.zig");
const Arg = @import("Arg.zig");
const c = @import("common.zig");
const Self = @This();

name: []const u8,
type: ?[]const u8 = null,
since: ?[]const u8 = null,
deprecated_since: ?[]const u8 = null,
description: ?Description = null,
args: std.ArrayList(Arg),
fn_name: []const u8,
destructor: bool = false,
numeric_since: ?u32 = null,
numeric_deprecated_since: ?u32 = null,
fd_count: usize = 0,
opcode: u32 = 0,
allocator: std.mem.Allocator,

pub fn init(allocator: std.mem.Allocator, parser: *Parser) !Self {
    var self = Self{
        .name = undefined,
        .args = std.ArrayList(Arg).init(allocator),
        .fn_name = undefined,
        .allocator = allocator,
    };

    const parse_elems = !parser.isSelfClosingElement();

    while (parser.getNextAttributeName()) |attrib| {
        if (std.mem.eql(u8, attrib, "name")) {
            self.name = parser.getNextAttributeValue().?;
            self.fn_name = try c.snakeToCamel(self.allocator, self.name);
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

    if (parse_elems) {
        while (parser.getNextElementName()) |elem| {
            if (std.mem.eql(u8, elem, "/request")) break;
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
    }

    return self;
}

pub fn deinit(self: Self) void {
    self.allocator.free(self.fn_name);
    for (self.args.items) |arg| arg.deinit();
    self.args.deinit();
}

pub fn write(self: Self, writer: std.fs.File.Writer) !void {
    if (self.description) |description| try description.emit(writer, "\t///");
    const invalid_name = !std.zig.isValidId(self.fn_name);
    try writer.print("\tpub fn {s}{s}{s}(\n", .{
        if (invalid_name) "@\"" else "",
        self.fn_name,
        if (invalid_name) "\"" else "",
    });
    try writer.print("\t\tself: @This(),\n", .{});
    const is_destructor = self.type != null and std.mem.eql(u8, self.type.?, "destructor");

    const is_constructor = for (self.args.items) |arg| {
        if (arg.enumerated_type == .new_id) break true;
    } else false;

    if (is_destructor) {
        try self.printDestructorArgs(writer);
    } else if (is_constructor) {
        try self.printConstructorArgs(writer);
    } else {
        try self.printNormalArgs(writer);
    }

    try writer.print("\t}}\n", .{});
}

fn printDestructorArgs(self: Self, writer: std.fs.File.Writer) !void {
    for (self.args.items) |arg| {
        try arg.write(writer);
    }
    try writer.print("\t) void {{\n", .{});
    try writer.print("\t\tself.proxy.marshalDestroyArgs({d}, {d}, .{{\n", .{ self.fd_count, self.opcode });
    for (self.args.items) |arg| {
        try writer.print("\t\t\t{s},\n", .{arg.final_name orelse arg.name});
    }
    try writer.print("\t\t}});\n", .{});
}

fn printConstructorArgs(self: Self, writer: std.fs.File.Writer) !void {
    for (self.args.items) |arg| {
        if (arg.enumerated_type == .new_id) {
            if (arg.interface_type == null) {
                try writer.print("\t\tcomptime Interface: type,\n", .{});
                try writer.print("\t\tversion: u32,\n", .{});
            }
            continue;
        }
        try arg.write(writer);
    }

    const return_type = for (self.args.items) |arg| {
        if (arg.enumerated_type == .new_id) break arg.interface_type orelse "Interface";
    } else unreachable;

    try writer.print("\t) !{s} {{\n", .{return_type});

    try writer.print("\t\tconst new_id = try self.proxy.id_allocator.allocate(.client);\n", .{});
    try writer.print(
        "\t\treturn self.proxy.marshalCreateArgs({s}, {d}, new_id, {d}, .{{\n",
        .{ return_type, self.fd_count, self.opcode },
    );
    for (self.args.items) |arg| {
        if (arg.enumerated_type == .new_id) {
            if (arg.interface_type == null) {
                try writer.print("\t\t\tGenericNewId{{\n", .{});
                try writer.print("\t\t\t\t.interface = Interface.interface,\n", .{});
                try writer.print("\t\t\t\t.version = version,\n", .{});
                try writer.print("\t\t\t\t.id = new_id,\n", .{});
                try writer.print("\t\t\t}},\n", .{});
            } else {
                try writer.print("\t\t\tnew_id,\n", .{});
            }
            continue;
        }
        try writer.print("\t\t\t{s},\n", .{arg.final_name orelse arg.name});
    }
    try writer.print("\t\t}});\n", .{});
}

fn printNormalArgs(self: Self, writer: std.fs.File.Writer) !void {
    for (self.args.items) |arg| {
        try arg.write(writer);
    }
    try writer.print("\t) !void {{\n", .{});
    try writer.print("\t\ttry self.proxy.marshalArgs({d}, {d}, .{{\n", .{ self.fd_count, self.opcode });
    for (self.args.items) |arg| {
        try writer.print("\t\t\t{s},\n", .{arg.final_name orelse arg.name});
    }
    try writer.print("\t\t}});\n", .{});
}
