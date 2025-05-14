pub usingnamespace @import("wayland_client_protocol");
pub const DisplayConnection = @import("DisplayConnection.zig");
pub const Fixed = @import("core").Fixed;

test {
    @import("std").testing.refAllDecls(@This());
}
