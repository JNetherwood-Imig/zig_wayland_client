pub usingnamespace @import("wayland_client_protocol");
pub const DisplayConnection = @import("DisplayConnection.zig");
pub const Fixed = @import("core").Fixed;
pub const os = @import("os");

test {
    @import("std").testing.refAllDecls(@This());
}
