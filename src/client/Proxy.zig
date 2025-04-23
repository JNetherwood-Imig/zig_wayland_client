/// This interface is responsible for serializing messages from a tuple of args
/// int --> i32,
/// uint --> u32,
/// Fixed --> i32,
/// string --> .{u32, ...:0}
/// object<T> --> T orelse u32 --> u32,
/// new_id<T> --> u32 orelse .{string, u32, u32}
/// array --> .{u32, ...}
/// fd --> ancillary (TODO research)
id: Id,
event0_index: usize,
socket: posix.Socket,
id_allocator: *IdAllocator,

const Int = i32;
const Uint = u32;
const Fixed = @import("../common/Fixed.zig");
const String = [:0]const u8;
const Object = Proxy;
const NewId = u32;
const AnonymousNewId = struct {
    interface: String,
    version: u32,
    new_id: u32,
};
const Array = []const u8;
const Fd = posix.File;

const wl = @import("client_protocol");

fn wlDisplayGetRegistry(self: Proxy) !wl.Registry {
    return self.marshalCreateArgs(wl.Registry, .{self.id_allocator.allocate(.client)});
}
fn wlRegistryBind(self: Proxy, comptime T: type, name: u32, interface: [*:0]const u8, version: u32) !T {
    return self.marshalCreateArgs(T, .{
        name,
        AnonymousNewId{
            .interface = interface,
            .version = version,
            .new_id = self.id_allocator.allocate(.client),
        },
    });
}

pub const MarshalCreateArgsError = error{};

pub fn marshalCreateArgs(self: Proxy, comptime T: type, args: anytype) MarshalCreateArgsError!T {
    _ = self;
    _ = args;
    return T{};
}

pub const MarshalArgsError = error{};

pub fn marshalArgs(self: Proxy, args: anytype) MarshalArgsError!void {
    _ = self;
    inline for (@typeInfo(args).@"struct".fields) |field| {
        switch (field.type) {
            i32 => {},
            u32 => {},
            Fixed => {},
            String => {},
            Proxy => {},
            AnonymousNewId => {},
            Array => {},
            Fd => {},
        }
    }
}

pub fn marshalDestroyArgs(self: Proxy, args: anytype) void {
    self.marshalArgs(args) catch {};
}

const Proxy = @This();

const IdAllocator = @import("../common/IdAllocator.zig");
const Id = IdAllocator.Id;
const posix = @import("util").posix;
