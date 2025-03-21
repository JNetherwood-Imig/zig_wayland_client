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

    try ctx.writeProtocols();
}
