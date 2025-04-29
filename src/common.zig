pub const Fixed = @import("common/Fixed.zig");
pub const IdAllocator = @import("common/IdAllocator.zig");
pub const Proxy = @import("common/Proxy.zig");
pub usingnamespace @import("common/message_utils.zig");

test {
    @import("std").testing.refAllDecls(@This());
}
