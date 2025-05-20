//! The core module holds dependencies of both wayland_client and the to-be-generated wayland_client_protocol

pub const message_utils = @import("core/message_utils.zig");
pub const proxy_manager = @import("core/proxy_manager.zig");
pub const Fixed = @import("core/Fixed.zig");
pub const Proxy = @import("core/Proxy.zig");

test {
    @import("std").testing.refAllDecls(@This());
}
