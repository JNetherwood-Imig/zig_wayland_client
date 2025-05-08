const std = @import("std");
const Parser = @import("Parser.zig");
const Protocol = @import("Protocol.zig");

const Self = @This();

allocator: std.mem.Allocator,
out_file: ?std.fs.File = null,
writer: std.fs.File.Writer,
files: std.ArrayList(std.fs.File),
protocols: std.ArrayList(Protocol),
dependencies: std.ArrayList(DependencyInfo),
mode: Mode,

pub const Mode = enum(u1) {
    client,
    server,
};

pub fn init(allocator: std.mem.Allocator, mode: Mode) Self {
    return .{
        .allocator = allocator,
        .files = std.ArrayList(std.fs.File).init(allocator),
        .protocols = std.ArrayList(Protocol).init(allocator),
        .writer = std.io.getStdOut().writer(),
        .dependencies = std.ArrayList(DependencyInfo).init(allocator),
        .mode = mode,
    };
}

pub fn deinit(self: Self) void {
    if (self.out_file) |f| f.close();
    self.dependencies.deinit();
    for (self.protocols.items) |protocol| protocol.deinit();
    self.protocols.deinit();
    self.files.deinit();
}

pub fn addFile(self: *Self, file: std.fs.File) !void {
    try self.files.append(file);
}

pub fn writeProtocols(self: *Self) !void {
    switch (self.mode) {
        .client => try writeClientProtocols(self),
        .server => try writeServerProtocols(self),
    }
}

fn writeClientProtocols(self: *Self) !void {
    try self.writer.writeAll("pub const Proxy = @import(\"deps/Proxy.zig\");\n");
    for (self.files.items) |file| {
        const protocol = try Protocol.init(self.allocator, file);
        try self.protocols.append(protocol);
        for (protocol.interfaces.items) |interface| try self.dependencies.append(DependencyInfo{
            .interface = interface.type_name,
            .protocol = protocol.name,
        });
    }

    for (self.protocols.items) |*protocol| {
        try protocol.finalize();
        try self.writer.print("pub usingnamespace @import(\"{s}.zig\");\n", .{protocol.name});
    }

    const event_file = try std.fs.cwd().createFile("event.zig", .{});
    defer event_file.close();
    const event_writer = event_file.writer();

    for (self.protocols.items) |protocol| {
        try event_writer.print("const {s} = @import(\"{s}.zig\");\n", .{ protocol.name, protocol.name });
    }
    try event_writer.print("pub const EventType = enum(u32) {{\n", .{});
    for (self.protocols.items) |protocol| {
        for (protocol.interfaces.items) |interface| {
            for (interface.events.items) |event| {
                try event_writer.print("\t{s}_{s},\n", .{ std.mem.trimLeft(u8, interface.name, "wl_"), event.name });
            }
        }
    }
    try event_writer.print("}};\n", .{});
    try event_writer.print("pub const Event = union(EventType) {{\n", .{});
    for (self.protocols.items) |protocol| {
        for (protocol.interfaces.items) |interface| {
            for (interface.events.items) |event| {
                try event_writer.print("\t{s}_{s}: {s}.{s}.{s}Event,\n", .{
                    std.mem.trimLeft(u8, interface.name, "wl_"),
                    event.name,
                    protocol.name,
                    interface.type_name,
                    event.type_name,
                });
            }
        }
    }
    try event_writer.writeAll(
        \\    pub fn deinit(self: @This()) void {
        \\        switch (self) {
        \\            inline else => |child| child.deinit(),
        \\        }
        \\    }
        \\
    );
    try event_writer.print("}};\n", .{});

    try self.writer.print("pub usingnamespace @import(\"event.zig\");\n", .{});

    for (self.protocols.items) |protocol| try protocol.writeClient(self.dependencies.items);
}

fn writeServerProtocols(self: *Self) !void {
    _ = self;
    // for (self.files.items) |file| {
    //     const protocol = try Protocol.init(self.allocator, file);
    //     try self.protocols.append(protocol);
    //     for (protocol.interfaces.items) |interface| try self.dependencies.append(DependencyInfo{
    //         .interface = interface.type_name,
    //         .protocol = protocol.name,
    //     });
    // }

    // for (self.protocols.items) |*protocol| {
    //     try protocol.finalize();
    //     try self.writer.print("pub usingnamespace @import(\"{s}.zig\");\n", .{protocol.name});
    // }
}

pub const DependencyInfo = struct {
    interface: []const u8,
    protocol: []const u8,
};
