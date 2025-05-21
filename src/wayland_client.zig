pub const connection = @import("wayland_client/connection.zig");
pub const os = @import("os");
pub const Fixed = @import("shared").Fixed;
pub usingnamespace @import("wayland_client_protocol");

test {
    @import("std").testing.refAllDecls(@This());
}
