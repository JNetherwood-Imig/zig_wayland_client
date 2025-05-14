//! The core module holds dependencies of both wayland_client and the to-be-generated wayland_client_protocol

pub const message_utils = @import("core/message_utils.zig");
pub const Fixed = @import("core/Fixed.zig");
pub const ProxyManager = @import("core/ProxyManager.zig");
pub const Proxy = @import("core/Proxy.zig");

test {
    @import("std").testing.refAllDecls(@This());
}
