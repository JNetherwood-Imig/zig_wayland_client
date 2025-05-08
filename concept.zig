const std = @import("std");

const String = [:0]const u8;
const Array = []const u8;

const wl = struct {
    const Proxy = struct {
        display_connection: *DisplayConnection,
        id: u32,
        event0_index: u32,

        pub fn marshalArgs(self: *const Proxy, args: anytype) !void {
            _ = self;
            _ = args;
        }

        pub fn marshalCreateArgs(self: *const Proxy, comptime T: type, args: anytype) !*T {
            const new_proxy = try self.display_connection.allocProxy();
            new_proxy.event0_index = T.event0_index;
            try new_proxy.marshalArgs(args);
            return @ptrCast(new_proxy);
        }

        pub fn marshalDestroyArgs(self: *const Proxy, args: anytype) void {
            self.marshalArgs(args) catch {};
        }
    };

    pub const DisplayConnection = struct {
        gpa: std.mem.Allocator,
        proxies: std.ArrayList(Proxy),

        pub fn allocProxy(self: *DisplayConnection) !*Proxy {
            return self.proxies.items[0];
        }
    };

    pub const Display = opaque {
        pub fn getRegistry(self: *Display) !*Registry {
            const proxy: *Proxy = @ptrCast(self);
            return proxy.marshalCreateArgs(Registry, .{});
        }

        pub fn sync(self: *Display) !*Callback {
            const proxy: *Proxy = @ptrCast(self);
            return proxy.marshalCreateArgs(Callback, .{});
        }

        pub const DeleteIdEvent = struct {
            self: *const Display,
            id: u32,
        };

        pub const ErrorEvent = struct {
            object_id: u32,
            code: Error,
            message: String,
        };

        pub const Error = enum(u32) {
            invalid_object = 0,
            invalid_method = 1,
            no_memory = 2,
            implementation = 3,
        };
    };

    pub const Registry = opaque {
        pub fn bind(self: *Registry, name: u32, comptime Interface: type, version: u32) !*const Interface {
            const proxy: Proxy = @ptrCast(self);
            return proxy.marshalCreateArgs(Interface, .{ name, version });
        }

        pub const GlobalEvent = struct {
            self: *Registry,
            name: u32,
            interface: String,
            version: u32,
        };

        pub const GlobalRemoveEvent = struct {
            self: *Registry,
            name: u32,
        };
    };

    pub const Callback = opaque {
        pub const DoneEvent = struct {
            self: *Callback,
            callback_data: u32,
        };
    };
};
