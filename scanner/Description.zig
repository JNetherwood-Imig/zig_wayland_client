const std = @import("std");
const Parser = @import("Parser.zig");
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

pub fn emit(self: Self, writer: std.fs.File.Writer, comment_prefix: []const u8) !void {
    if (self.text) |text| {
        var lines = std.mem.splitScalar(u8, text, '\n');
        while (lines.next()) |line| {
            const trimmed = std.mem.trim(u8, line, " \t\n");
            try writer.print("{s} {s}\n", .{ comment_prefix, trimmed });
        }
    }
}
