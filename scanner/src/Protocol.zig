const std = @import("std");
const Parser = @import("Parser.zig");
const Copyright = []const u8;
const Description = @import("Description.zig");
const Interface = @import("Interface.zig");
const DependencyInfo = @import("Context.zig").DependencyInfo;
const Self = @This();

name: []const u8,
copyright: ?Copyright = null,
description: ?Description = null,
interfaces: std.ArrayList(Interface),
allocator: std.mem.Allocator,
parser_buf: []const u8,
dependencies: std.ArrayList([]const u8),

pub fn init(allocator: std.mem.Allocator, file: std.fs.File) !Self {
    var parser = try Parser.init(allocator, file);
    var self = Self{
        .name = undefined,
        .allocator = allocator,
        .interfaces = std.ArrayList(Interface).init(allocator),
        .parser_buf = parser.buf,
        .dependencies = std.ArrayList([]const u8).init(allocator),
    };
    if (!std.mem.eql(u8, parser.getNextElementName().?, "protocol"))
        @panic("Expected a protocol definition");

    self.name = parser.getNextAttributeValue().?;

    while (parser.getNextElementName()) |elem| {
        if (std.mem.eql(u8, elem, "/protocol")) break;
        if (std.mem.eql(u8, elem, "copyright")) {
            self.copyright = parser.getNextText().?;
            _ = parser.getNextElementName().?;
            continue;
        }
        if (std.mem.eql(u8, elem, "description")) {
            self.description = Description.init(&parser);
            continue;
        }
        if (std.mem.eql(u8, elem, "interface")) {
            try self.interfaces.append(try Interface.init(self.allocator, &parser));
            continue;
        }

        unreachable;
    }

    return self;
}

pub fn deinit(self: Self) void {
    self.dependencies.deinit();
    self.allocator.free(self.parser_buf);
    for (self.interfaces.items) |interface| interface.deinit();
    self.interfaces.deinit();
}

pub fn finalize(self: *Self) !void {
    for (self.interfaces.items) |*interface| {
        for (interface.requests.items) |request| {
            for (request.args.items) |arg| {
                const t = if (arg.enum_type) |e|
                    e[0 .. std.mem.indexOfScalar(u8, e, '.') orelse e.len]
                else
                    arg.interface_type orelse continue;
                var provided = false;
                for (self.interfaces.items) |i| {
                    if (std.mem.eql(u8, t, i.type_name)) {
                        provided = true;
                        break;
                    }
                    for (i.enums.items) |e| {
                        if (std.mem.eql(u8, t, e.type_name)) {
                            provided = true;
                            break;
                        }
                    }
                }
                if (!provided) {
                    var needed = true;
                    for (self.dependencies.items) |d| {
                        if (std.mem.eql(u8, t, d)) {
                            needed = false;
                            break;
                        }
                    }
                    if (needed) try self.dependencies.append(t);
                }
            }
        }
        for (interface.events.items) |event| {
            for (event.args.items) |arg| {
                const t = if (arg.enum_type) |e|
                    e[0 .. std.mem.indexOfScalar(u8, e, '.') orelse e.len]
                else
                    arg.interface_type orelse continue;
                var provided = false;
                for (self.interfaces.items) |i| {
                    if (std.mem.eql(u8, t, i.type_name)) {
                        provided = true;
                        break;
                    }
                    for (i.enums.items) |e| {
                        if (std.mem.eql(u8, t, e.type_name)) {
                            provided = true;
                            break;
                        }
                    }
                }
                if (!provided) {
                    var needed = true;
                    for (self.dependencies.items) |d| {
                        if (std.mem.eql(u8, t, d)) {
                            needed = false;
                            break;
                        }
                    }
                    if (needed) try self.dependencies.append(t);
                }
            }
        }
        try interface.finalize();
    }
}

pub fn write(self: Self, deps: []const DependencyInfo) !void {
    var buf: [64]u8 = undefined;
    const out_path = try std.fmt.bufPrint(&buf, "{s}.zig", .{self.name});
    const out_file = try std.fs.cwd().createFile(out_path, .{});
    defer out_file.close();
    const writer = out_file.writer();

    try self.printCopyright(writer);
    try self.printDescription(writer);

    try writer.print("const std = @import(\"std\");\n", .{});
    try writer.print("const common = @import(\"common\");\n", .{});
    try writer.print("const Proxy = common.Proxy;\n", .{});
    try writer.print("const GenericNewId = Proxy.GenericNewId;\n", .{});

    for (self.dependencies.items) |dep| {
        var found = false;
        for (deps) |d| {
            if (std.mem.eql(u8, d.interface, dep)) {
                try writer.print("const {s} = @import(\"{s}.zig\").{s};\n", .{ dep, d.protocol, dep });
                found = true;
                break;
            }
        }
        if (!found) std.debug.panic("Could not satisfy dependency {s} for {s}\n", .{ dep, self.name });
    }

    for (self.interfaces.items) |interface| {
        try interface.write(writer);
    }
}

fn printCopyright(self: Self, writer: std.fs.File.Writer) !void {
    if (self.copyright) |cr| {
        var lines = std.mem.splitScalar(u8, cr, '\n');
        while (lines.next()) |line| {
            const trimmed = std.mem.trim(u8, line, " \t\n");
            try writer.print("// {s}\n", .{trimmed});
        }
    }
}

fn printDescription(self: Self, writer: std.fs.File.Writer) !void {
    if (self.description) |description| try description.emit(writer, "//!");
}
