gpa: Allocator,
next_client: Id = client_min_id,
next_server: Id = server_min_id,
client_free_list: FreeList,
server_free_list: FreeList,

const client_min_id = 0x00000001;
const client_max_id = 0xf0ffffff;
const server_min_id = 0xff000000;
const server_max_id = 0xffffffff;

pub const Id = u32;

pub const Side = enum(u1) {
    client,
    server,
};

pub fn init(gpa: std.mem.Allocator) Self {
    return .{
        .gpa = gpa,
        .client_free_list = FreeList.init(gpa),
        .server_free_list = FreeList.init(gpa),
    };
}

pub fn deinit(self: Self) void {
    self.client_free_list.deinit();
    self.server_free_list.deinit();
}

pub fn getNext(self: *Self, side: Side) Id {
    switch (side) {
        .client => {
            if (self.client_free_list.items.len > 0) {
                return self.client_free_list.pop().?;
            }
            defer self.next_client += 1;
            return self.next_client;
        },
        .server => {
            if (self.server_free_list.items.len > 0) {
                return self.server_free_list.pop().?;
            }
            defer self.next_server += 1;
            return self.next_server;
        },
    }
}

pub const ReplaceError = Allocator.Error;

pub fn replace(self: *Self, id: u32) ReplaceError!void {
    if (id == self.next_client - 1) {
        self.next_client = id;
    } else if (id == self.next_server - 1) {
        self.next_server = id;
    } else if (id <= client_max_id) {
        try self.client_free_list.append(id);
        std.mem.sort(u32, self.client_free_list.items, {}, comptime std.sort.desc(u32));
    } else {
        try self.server_free_list.append(id);
        std.mem.sort(u32, self.server_free_list.items, {}, comptime std.sort.desc(u32));
    }
}

const Self = @This();

const std = @import("std");
const Allocator = std.mem.Allocator;
const FreeList = std.ArrayList(Id);
