gpa: Allocator,
next_client: u32,
next_server: u32,
client_free_list: FreeList,
server_free_list: FreeList,
mutex: Mutex,

const client_min_id = 0x00000002;
const client_max_id = 0xFEFFFFFF;
const server_min_id = 0xFF000000;
const server_max_id = 0xFFFFFFFF;

pub const Side = enum(u1) {
    client,
    server,
};

pub fn init(gpa: Allocator) IdAllocator {
    return .{
        .gpa = gpa,
        .next_client = client_min_id,
        .next_server = server_min_id,
        .client_free_list = FreeList.init(gpa, {}),
        .server_free_list = FreeList.init(gpa, {}),
        .mutex = .{},
    };
}

pub fn deinit(self: IdAllocator) void {
    self.client_free_list.deinit();
    self.server_free_list.deinit();
}

pub const AllocateError = error{
    ClientIdsExhausted,
    ServerIdsExhausted,
};

pub fn allocate(self: *IdAllocator, side: Side) AllocateError!u32 {
    self.mutex.lock();
    defer self.mutex.unlock();

    return switch (side) {
        .client => self.client_free_list.removeOrNull() orelse id: {
            if (self.next_client + 1 > client_max_id)
                return error.ClientIdsExhausted;
            defer self.next_client += 1;
            break :id self.next_client;
        },
        .server => self.server_free_list.removeOrNull() orelse id: {
            if (self.next_server + 1 > server_max_id)
                return error.ServerIdsExhausted;
            defer self.next_server += 1;
            break :id self.next_server;
        },
    };
}

test "allocate" {
    var alloc = IdAllocator.init(std.testing.allocator);
    defer alloc.deinit();

    const client = try alloc.allocate(.client);
    const client2 = try alloc.allocate(.client);
    const server = try alloc.allocate(.server);

    try testing.expectEqual(@as(u32, 2), client);
    try testing.expectEqual(@as(u32, 3), client2);
    try testing.expectEqual(@as(u32, server_min_id), server);
}

pub const ReplaceError = Allocator.Error;

pub fn replace(self: *IdAllocator, id: u32) ReplaceError!void {
    self.mutex.lock();
    defer self.mutex.unlock();
    if (id == self.next_client - 1) {
        self.next_client = id;
    } else if (id == self.next_server - 1) {
        self.next_server = id;
    } else if (id <= client_max_id) {
        try self.client_free_list.add(id);
    } else {
        try self.server_free_list.add(id);
    }
}

test "replace" {
    var alloc = IdAllocator.init(std.testing.allocator);
    defer alloc.deinit();

    const client2 = try alloc.allocate(.client);
    const client3 = try alloc.allocate(.client);

    try testing.expectEqual(@as(u32, 2), client2);
    try testing.expectEqual(@as(u32, 3), client3);

    try alloc.replace(client3);
    const client4 = try alloc.allocate(.client);

    try testing.expectEqual(@as(u32, 3), client4);

    try alloc.replace(client2);
    const client5 = try alloc.allocate(.client);

    try testing.expectEqual(@as(u32, 2), client5);
}

const IdAllocator = @This();

const std = @import("std");
const Allocator = std.mem.Allocator;
const FreeList = std.PriorityQueue(u32, void, struct {
    pub fn lessThan(_: void, a: u32, b: u32) std.math.Order {
        return std.math.order(a, b);
    }
}.lessThan);
const Mutex = std.Thread.Mutex;
const testing = std.testing;
