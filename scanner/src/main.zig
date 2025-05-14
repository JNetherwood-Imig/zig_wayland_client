const std = @import("std");

const Context = @import("Context.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    var ctx = Context.init(allocator);
    defer ctx.deinit();

    var provided_core_path: ?[]const u8 = null;
    for (args[1..]) |arg| {
        if (std.mem.startsWith(u8, arg, "-o")) {
            if (ctx.out_file != null) {
                std.log.err("Cannot specify multiple output files", .{});
                return error.InvalidArguments;
            }
            ctx.out_file = try std.fs.cwd().createFile(arg[2..], .{});
            ctx.writer = ctx.out_file.?.writer();
            continue;
        }
        if (std.mem.startsWith(u8, arg, "-o")) {
            provided_core_path = arg[2..];
            continue;
        }
        if (std.mem.startsWith(u8, arg, "-e")) {
            try ctx.addFile(try std.fs.cwd().openFile(arg[2..], .{}));
            continue;
        }

        // TODO print usage (goes with invalid args/usage above)
        std.log.err("Unrecognized argument \"{s}\"", .{arg});
        return error.InvalidArguments;
    }

    var have_wayland_xml: bool = false;
    if (provided_core_path) |path| {
        have_wayland_xml = true;
        try ctx.files.insert(0, try std.fs.cwd().openFile(path, .{}));
    } else {
        if (std.posix.getenv("XDG_DATA_HOME")) |data_home| {
            var dir = try std.fs.openDirAbsolute(data_home, .{});
            defer dir.close();
            if (dir.openFile("wayland/wayland.xml", .{}) catch null) |file| {
                try ctx.files.insert(0, file);
                have_wayland_xml = true;
            }
        }
        if (!have_wayland_xml) {
            const data_dirs = std.posix.getenv("XDG_DATA_DIRS") orelse return error.NoXdgDataDirs;
            var it = std.mem.splitScalar(u8, data_dirs, ':');
            while (it.next()) |dirname| {
                var dir = std.fs.openDirAbsolute(dirname, .{}) catch continue;
                defer dir.close();
                if (dir.openFile("wayland/wayland.xml", .{}) catch null) |file| {
                    try ctx.files.insert(0, file);
                    have_wayland_xml = true;
                    break;
                }
            }
        }
    }

    if (!have_wayland_xml) {
        @panic("Cannot find wayland xml, and none was provided.");
    }

    try ctx.writeProtocols();
}
