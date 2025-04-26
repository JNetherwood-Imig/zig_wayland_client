const std = @import("std");
const Parser = @import("Parser.zig");
const Description = @import("Description.zig");
const Request = @import("Request.zig");
const Event = @import("Event.zig");
const Enum = @import("Enum.zig");
const c = @import("common.zig");
const Self = @This();

name: []const u8,
version: []const u8,
description: ?Description = null,
requests: std.ArrayList(Request),
events: std.ArrayList(Event),
enums: std.ArrayList(Enum),
type_name: []const u8,
numeric_version: u32,
allocator: std.mem.Allocator,

pub fn init(allocator: std.mem.Allocator, parser: *Parser) !Self {
    var self = Self{
        .name = undefined,
        .version = undefined,
        .requests = std.ArrayList(Request).init(allocator),
        .events = std.ArrayList(Event).init(allocator),
        .enums = std.ArrayList(Enum).init(allocator),
        .type_name = undefined,
        .numeric_version = 1,
        .allocator = allocator,
    };

    while (parser.getNextAttributeName()) |attrib| {
        if (std.mem.eql(u8, attrib, "name")) {
            self.name = parser.getNextAttributeValue().?;
            self.type_name = try c.snakeToPascal(self.allocator, std.mem.trimLeft(u8, self.name, "wl_"));
            continue;
        }
        if (std.mem.eql(u8, attrib, "version")) {
            self.version = parser.getNextAttributeValue().?;
            continue;
        }

        unreachable;
    }

    while (parser.getNextElementName()) |elem| {
        if (std.mem.eql(u8, elem, "/interface")) break;
        if (std.mem.eql(u8, elem, "description")) {
            self.description = Description.init(parser);
            continue;
        }
        if (std.mem.eql(u8, elem, "request")) {
            try self.requests.append(try Request.init(self.allocator, parser));
            continue;
        }
        if (std.mem.eql(u8, elem, "event")) {
            try self.events.append(try Event.init(self.allocator, parser, self));
            continue;
        }
        if (std.mem.eql(u8, elem, "enum")) {
            try self.enums.append(try Enum.init(self.allocator, parser));
            continue;
        }

        unreachable;
    }

    return self;
}

pub fn deinit(self: Self) void {
    self.allocator.free(self.type_name);
    for (self.requests.items) |request| request.deinit();
    self.requests.deinit();
    for (self.events.items) |event| event.deinit();
    self.events.deinit();
    for (self.enums.items) |@"enum"| @"enum".deinit();
    self.enums.deinit();
}

pub fn finalize(self: *Self) !void {
    for (self.requests.items, 0..) |*request, opcode| {
        request.opcode = @intCast(opcode);
        for (request.args.items) |*arg| {
            var invalid_name = false;
            for (self.requests.items) |r| {
                if (std.mem.eql(u8, arg.name, r.fn_name)) {
                    invalid_name = true;
                    break;
                }
            }
            if (invalid_name) arg.final_name = try std.fmt.allocPrint(self.allocator, "_{s}", .{arg.name});
        }
    }
}

pub fn write(self: Self, writer: std.fs.File.Writer) !void {
    if (self.description) |description| try description.emit(writer, "///");

    try writer.print("pub const {s} = struct {{\n", .{self.type_name});

    try writer.print("\tproxy: @import(\"common\").Proxy,\n", .{});

    try writer.print("\tpub const interface = \"{s}\";\n", .{self.name});

    if (self.events.items.len > 0) {
        try writer.print(
            "\tpub const event0_index: u32 = @intFromEnum(@import(\"event.zig\").Event.{s}_{s});\n",
            .{ std.mem.trimLeft(u8, self.name, "wl_"), self.events.items[0].name },
        );
    } else {
        try writer.print("\tpub const event0_index: u32 = 0;\n", .{});
    }

    for (self.requests.items) |request| try request.write(writer);
    for (self.events.items) |event| try event.write(writer);
    for (self.enums.items) |@"enum"| try @"enum".write(writer);
    try writer.print("}};\n", .{});
}
