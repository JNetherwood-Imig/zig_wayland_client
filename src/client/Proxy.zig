id: Id,
event0_index: usize,
socket: posix.Socket,
id_allocator: *IdAllocator,

pub fn marshalCreateFlags(comptime T: type, flags: anytype) !T {
    _ = flags;
    return T{};
}

pub fn marshalFlags(self: Self, flags: anytype) !void {
    _ = self;
    _ = flags;
}

pub fn marshalDestroyFlags(self: Self, flags: anytype) void {
    _ = self;
    _ = flags;
}

const Self = @This();

const IdAllocator = @import("../common/IdAllocator.zig");
const Id = IdAllocator.Id;
const posix = @import("../util/posix.zig");
