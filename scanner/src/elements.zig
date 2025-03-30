const std = @import("std");

const Parser = @import("Parser.zig");
const DependencyInfo = @import("Context.zig").DependencyInfo;

pub const Protocol = struct {
    // Attributes
    name: []const u8,

    // Elements
    copyright: ?Copyright = null,
    description: ?Description = null,
    interfaces: std.ArrayList(Interface),

    allocator: std.mem.Allocator,
    parser_buf: []const u8,

    dependencies: std.ArrayList([]const u8),

    const Self = @This();

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
        try writer.print("const Object = @import(\"Object.zig\");\n", .{});

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
        if (self.description) |description| try description.write(writer, "//!");
    }
};

pub const Copyright = []const u8;

pub const Interface = struct {
    // Attributes
    name: []const u8,
    version: []const u8,

    // Elements
    description: ?Description = null,
    requests: std.ArrayList(Request),
    events: std.ArrayList(Event),
    enums: std.ArrayList(Enum),

    // Parsed data
    type_name: []const u8,
    numeric_version: u32,

    allocator: std.mem.Allocator,

    const Self = @This();

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
                if (std.mem.eql(u8, self.name, "wl_display")) {
                    while (parser.getNextElementName()) |elem| {
                        if (std.mem.eql(u8, elem, "interface")) {
                            self.name = parser.getNextAttributeValue().?;
                            break;
                        }
                    }
                }
                self.type_name = try snakeToPascal(self.allocator, std.mem.trimLeft(u8, self.name, "wl_"));
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
                try self.events.append(try Event.init(self.allocator, parser));
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
        if (self.description) |description| try description.write(writer, "///");
        try writer.print("pub const {s} = struct {{\n", .{self.type_name});
        try writer.print("\tproxy: Object,\n", .{});
        try writer.print("\tpub const interface = \"{s}\";\n", .{self.name});
        if (self.events.items.len > 0) {
            try writer.print(
                "\tpub const event0_index: u32 = @intFromEnum(@import(\"event.zig\").Event.{s}_{s});\n",
                .{ self.name, self.events.items[0].name },
            );
        } else {
            try writer.print("\tpub const event0_index: u32 = 0;\n", .{});
        }
        for (self.requests.items) |request| try request.write(writer);
        for (self.events.items) |event| try event.write(writer);
        for (self.enums.items) |@"enum"| try @"enum".write(writer);
        try writer.print("}};\n", .{});
    }
};

pub const Request = struct {
    // Attributes
    name: []const u8,
    type: ?[]const u8 = null,
    since: ?[]const u8 = null,
    deprecated_since: ?[]const u8 = null,

    // Elements
    description: ?Description = null,
    args: std.ArrayList(Arg),

    // Parsed data
    fn_name: []const u8,
    destructor: bool = false,
    numeric_since: ?u32 = null,
    numeric_deprecated_since: ?u32 = null,
    opcode: u32 = 0,

    allocator: std.mem.Allocator,

    const Self = @This();

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
                self.fn_name = try snakeToCamel(self.allocator, self.name);
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
                    try self.args.append(try Arg.init(self.allocator, parser));
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
        if (self.description) |description| try description.write(writer, "\t///");
        const invalid_name = !std.zig.isValidId(self.fn_name);
        try writer.print("\tpub fn {s}{s}{s}(\n", .{
            if (invalid_name) "@\"" else "",
            self.fn_name,
            if (invalid_name) "\"" else "",
        });
        try writer.print("\t\tself: @This(),\n", .{});
        const is_destructor = self.type != null and std.mem.eql(u8, self.type.?, "destructor");

        const is_constructor = blk: {
            for (self.args.items) |arg| {
                if (arg.enumerated_type == .new_id) {
                    break :blk true;
                }
            }
            break :blk false;
        };

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
        try writer.print("\t\tself.proxy.sendDestroyRequest({d}, .{{\n", .{self.opcode});
        for (self.args.items) |arg| {
            try writer.print("\t\t\tObject.Arg{{ .{s} = {s} }},\n", .{
                @tagName(arg.enumerated_type),
                arg.final_name orelse arg.name,
            });
        }
        try writer.print("\t\t}});\n", .{});
    }

    fn printConstructorArgs(self: Self, writer: std.fs.File.Writer) !void {
        for (self.args.items) |arg| {
            if (arg.enumerated_type == .new_id) {
                if (arg.interface_type == null) {
                    try writer.print("\t\tcomptime Interface: type,\n", .{});
                    try writer.print("\t\tcomptime version: u32,\n", .{});
                }
                continue;
            }
            try arg.write(writer);
        }

        const return_type = for (self.args.items) |arg| {
            if (arg.enumerated_type == .new_id) break arg.interface_type orelse "Interface";
        } else unreachable;

        try writer.print("\t) !{s} {{\n", .{return_type});

        try writer.print("\t\treturn try self.proxy.sendCreateRequest({s}, self.proxy.display, {d}, .{{\n", .{
            return_type,
            self.opcode,
        });
        for (self.args.items) |arg| {
            if (arg.enumerated_type != .new_id) {
                try writer.print("\t\t\tObject.Arg{{ .{s} = {s} }},\n", .{
                    @tagName(arg.enumerated_type),
                    arg.final_name orelse arg.name,
                });
            } else {
                try writer.print("\t\t\tObject.Arg{{ .new_id = .{{\n", .{});
                if (arg.interface == null) {
                    try writer.print("\t\t\t\t.interface = Interface.interface,\n", .{});
                    try writer.print("\t\t\t\t.version = version,\n", .{});
                }
                try writer.print("\t\t\t}}}},\n", .{});
            }
        }
        try writer.print("\t\t}});\n", .{});
    }

    fn printNormalArgs(self: Self, writer: std.fs.File.Writer) !void {
        for (self.args.items) |arg| {
            try arg.write(writer);
        }
        try writer.print("\t) !void {{\n", .{});
        try writer.print("\t\t_ = try self.proxy.sendRequest(null, {d}, .{{\n", .{self.opcode});
        for (self.args.items) |arg| {
            try writer.print("\t\t\tObject.Arg{{ .{s} = {s} }},\n", .{
                @tagName(arg.enumerated_type),
                arg.final_name orelse arg.name,
            });
        }
        try writer.print("\t\t}});\n", .{});
    }
};

pub const Event = struct {
    // Attributes
    name: []const u8,
    type: ?[]const u8 = null,
    since: ?[]const u8 = null,
    deprecated_since: ?[]const u8 = null,

    // Elements
    description: ?Description = null,
    args: std.ArrayList(Arg),

    // Parsed data
    type_name: []const u8,
    numeric_since: ?u32 = null,
    numeric_deprecated_since: ?u32 = null,

    allocator: std.mem.Allocator,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, parser: *Parser) !Self {
        var self = Self{
            .name = undefined,
            .args = std.ArrayList(Arg).init(allocator),
            .type_name = undefined,
            .allocator = allocator,
        };

        while (parser.getNextAttributeName()) |attrib| {
            if (std.mem.eql(u8, attrib, "name")) {
                self.name = parser.getNextAttributeValue().?;
                self.type_name = try snakeToPascal(allocator, self.name);
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
                try self.args.append(try Arg.init(self.allocator, parser));
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
        if (self.description) |description| try description.write(writer, "\t///");
        try writer.print("\tpub const {s}Event = struct {{\n", .{self.type_name});
        for (self.args.items) |arg| try arg.write(writer);
        try writer.print("\t}};\n", .{});
    }
};

pub const Enum = struct {
    // Attributes
    name: []const u8,
    since: ?[]const u8 = null,
    bitfield: ?[]const u8 = null,

    // Elements
    description: ?Description = null,
    entries: std.ArrayList(Entry),

    // Parsed data
    type_name: []const u8,
    numeric_since: ?u32 = null,
    is_bitfield: bool = false,

    allocator: std.mem.Allocator,

    const Self = @This();

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
                self.type_name = try snakeToPascal(self.allocator, self.name);
                continue;
            }
            if (std.mem.eql(u8, attrib, "since")) {
                self.since = parser.getNextAttributeValue().?;
                continue;
            }
            if (std.mem.eql(u8, attrib, "bitfield")) {
                self.bitfield = parser.getNextAttributeValue().?;
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
        if (self.description) |description| try description.write(writer, "\t///");
        try writer.print("\tpub const {s} = enum(u32) {{\n", .{self.type_name});
        for (self.entries.items) |entry| try entry.write(writer);
        try writer.print("\t}};\n", .{});
    }
};

pub const Entry = struct {
    // Attributes
    name: []const u8,
    value: []const u8,
    summary: ?[]const u8 = null,
    since: ?[]const u8 = null,
    deprecated_since: ?[]const u8 = null,

    // Elements
    description: ?Description = null,

    // Parsed data
    numeric_since: ?u32 = null,
    numeric_deprecated_since: ?u32 = null,

    const Self = @This();

    pub fn init(parser: *Parser) !Self {
        var self = Self{
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

    pub fn write(self: Self, writer: std.fs.File.Writer) !void {
        if (self.description) |description| {
            try description.write(writer, "\t\t///");
        } else if (self.summary) |summary| {
            var lines = std.mem.splitScalar(u8, summary, '\n');
            while (lines.next()) |line| {
                try writer.print("\t\t/// {s}\n", .{line});
            }
        }

        const invalid_name = !std.zig.isValidId(self.name);
        try writer.print("\t\t{s}{s}{s} = {s},\n", .{
            if (invalid_name) "@\"" else "",
            self.name,
            if (invalid_name) "\"" else "",
            self.value,
        });
    }
};

pub const Arg = struct {
    // Attributes
    name: []const u8,
    type: []const u8,
    summary: ?[]const u8 = null,
    interface: ?[]const u8 = null,
    allow_null: ?[]const u8 = null,
    @"enum": ?[]const u8 = null,

    // Elements
    description: ?Description = null,

    // Parsed data
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

    const Self = @This();

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
                self.interface_type = try snakeToPascal(self.allocator, std.mem.trimLeft(u8, self.interface.?, "wl_"));
                continue;
            }
            if (std.mem.eql(u8, attrib, "allow-null")) {
                self.allow_null = parser.getNextAttributeValue().?;
                self.nullable = std.mem.eql(u8, self.allow_null.?, "true");
                continue;
            }
            if (std.mem.eql(u8, attrib, "enum")) {
                self.@"enum" = parser.getNextAttributeValue().?;
                self.enum_type = try snakeToPascal(self.allocator, std.mem.trimLeft(u8, self.@"enum".?, "wl_"));
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
            try description.write(writer, "\t\t///");
        } else if (self.summary) |summary| try writer.print("\t\t/// {s}\n", .{summary});
        try writer.print("\t\t{s}: {s}{s},\n", .{
            self.final_name orelse self.name,
            if (self.nullable) "?" else "",
            type_str,
        });
    }
};

pub const Description = struct {
    const Self = @This();

    summary: []const u8,

    text: ?[]const u8 = null,

    pub fn init(parser: *Parser) Self {
        return .{
            .summary = parser.getNextAttributeValue().?,
            .text = blk: {
                if (!parser.isSelfClosingElement()) {
                    defer _ = parser.getNextElementName();
                    break :blk parser.getNextText().?;
                } else {
                    break :blk null;
                }
            },
        };
    }

    pub fn write(self: Description, writer: std.fs.File.Writer, comment_prefix: []const u8) !void {
        if (self.text) |text| {
            var lines = std.mem.splitScalar(u8, text, '\n');
            while (lines.next()) |line| {
                const trimmed = std.mem.trim(u8, line, " \t\n");
                try writer.print("{s} {s}\n", .{ comment_prefix, trimmed });
            }
        }
    }
};

fn snakeToCamel(allocator: std.mem.Allocator, snake: []const u8) ![]const u8 {
    var result = std.ArrayList(u8).init(allocator);
    var capitalize_next = false;
    for (snake) |c| {
        if (c == '_') {
            capitalize_next = true;
            continue;
        }
        try result.append(if (capitalize_next) std.ascii.toUpper(c) else c);
        capitalize_next = false;
    }

    return try result.toOwnedSlice();
}

fn snakeToPascal(allocator: std.mem.Allocator, snake: []const u8) ![]const u8 {
    var result = std.ArrayList(u8).init(allocator);
    var capitalize_next = true;
    for (snake) |c| {
        if (c == '_') {
            capitalize_next = true;
            continue;
        }
        if (c == '.') {
            capitalize_next = true;
            try result.append(c);
            continue;
        }
        try result.append(if (capitalize_next) std.ascii.toUpper(c) else c);
        capitalize_next = false;
    }

    return try result.toOwnedSlice();
}
