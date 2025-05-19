pub usingnamespace @import("wayland_client_protocol");
pub const connection = @import("connection.zig");
pub const Fixed = @import("core").Fixed;
pub const os = @import("os");

test {
    @import("std").testing.refAllDecls(@This());
}
