const std = @import("std");

const Context = @import("Context.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    const mode: Context.Mode = if (std.mem.eql(u8, args[1], "client"))
        .client
    else if (std.mem.eql(u8, args[1], "server"))
        .server
    else
        std.debug.panic("Expected a mode argument but got {s}", .{args[1]});

    var ctx = Context.init(allocator, mode);
    defer ctx.deinit();

    var provided_core_path: ?[]const u8 = null;
    for (args[2..]) |arg| {
        if (std.mem.startsWith(u8, arg, "-o")) {
            if (ctx.out_file != null) {
                std.log.err("Cannot specify multiple output files", .{});
                return error.InvalidArguments;
            }
            ctx.out_file = try std.fs.cwd().createFile(arg[2..], .{});
            ctx.writer = ctx.out_file.?.writer();
            continue;
        }
        if (std.mem.startsWith(u8, arg, "-c")) {
            provided_core_path = arg[2..];
            continue;
        }
        if (std.mem.startsWith(u8, arg, "-f")) {
            try ctx.addFile(try std.fs.cwd().openFile(arg[2..], .{}));
            continue;
        }
        if (std.mem.startsWith(u8, arg, "-d")) {
            var dir = try std.fs.cwd().openDir(arg[2..], .{ .iterate = true });
            defer dir.close();
            var walker = try dir.walk(allocator);
            defer walker.deinit();

            while (try walker.next()) |entry| {
                if (!(entry.kind == .file and
                    std.mem.endsWith(u8, entry.basename, ".xml"))) continue;

                const file = try entry.dir.openFile(entry.basename, .{});
                errdefer file.close();
                try ctx.addFile(file);
            }
            continue;
        }

        // TODO print usage (goes with invalid args/usage above)
        std.log.err("Unrecognized argument \"{s}\"", .{arg});
        return error.InvalidArguments;
    }

    if (provided_core_path) |path| {
        try ctx.files.insert(0, try std.fs.cwd().openFile(path, .{}));
    } else {
        const path = "/usr/share/wayland/wayland.xml";
        try ctx.files.insert(0, try std.fs.openFileAbsolute(path, .{}));
    }

    try ctx.writeProtocols();
}
