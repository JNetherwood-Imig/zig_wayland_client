pub const File = @import("os/file.zig").File;
pub const Pipe = @import("os/Pipe.zig");
pub const Socket = @import("os/Socket.zig");
pub usingnamespace @import("os/poll.zig");

test {
    @import("std").testing.refAllDecls(@This());
}
