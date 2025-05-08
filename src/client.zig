pub usingnamespace @import("client_protocol");
pub const DisplayConnection = @import("client/DisplayConnection.zig");
pub const Fixed = @import("common").Fixed;

test {
    @import("std").testing.refAllDecls(@This());
}
