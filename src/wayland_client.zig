pub usingnamespace @import("protocol");
pub const DisplayConnection = @import("wayland_client/DisplayConnection.zig");
pub const Fixed = @import("shared").Fixed;

test {
    @import("std").testing.refAllDecls(@This());
}
