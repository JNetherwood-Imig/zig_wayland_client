const std = @import("std");

pub fn snakeToCamel(allocator: std.mem.Allocator, snake: []const u8) ![]const u8 {
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

pub fn snakeToPascal(allocator: std.mem.Allocator, snake: []const u8) ![]const u8 {
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
