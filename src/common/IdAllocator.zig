const std = @import("std");

const client_min_id = 0x00000001;
const client_max_id = 0xf0ffffff;
const server_min_id = 0xff000000;
const server_max_id = 0xffffffff;

allocator: std.mem.Allocator,
next_client: u32 = client_min_id,
next_server: u32 = server_min_id,
client_free_list: std.ArrayList(u32),
server_free_list: std.ArrayList(u32),

const Side = enum(u1) {
    client,
    server,
};

pub fn init(allocator: std.mem.Allocator) @This() {
    return .{
        .allocator = allocator,
        .client_free_list = std.ArrayList(u32).init(allocator),
        .server_free_list = std.ArrayList(u32).init(allocator),
    };
}

pub fn deinit(self: @This()) void {
    self.client_free_list.deinit();
    self.server_free_list.deinit();
}

pub fn allocate(self: @This(), side: Side) u32 {
    switch (side) {
        .client => {
            if (!self.client_free_list.items.len == 0) {
                return self.client_free_list.pop().?;
            }
            defer self.next_client += 1;
            return self.next_client;
        },
        .server => {
            if (!self.server_free_list.items.len == 0) {
                return self.server_free_list.pop().?;
            }
            defer self.next_server += 1;
            return self.next_server;
        },
    }
}

pub fn free(self: @This(), id: u32) void {
    std.mem.sort(u32, self.client_free_list.items, {}, comptime std.sort.desc(u32));
    if (id <= client_max_id) {
        self.client_free_list.append(id);
        std.mem.sort(u32, self.client_free_list.items, {}, comptime std.sort.desc(u32));
    } else {
        self.server_free_list.append(id);
        std.mem.sort(u32, self.server_free_list.items, {}, comptime std.sort.desc(u32));
    }
}
