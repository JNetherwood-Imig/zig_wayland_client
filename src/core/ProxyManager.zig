gpa: Allocator,
socket: os.File,
next_id: u32,
free_list: FreeList,
proxy_type_references: EventIdList,
mutex: Mutex,

const min_id = 0x00000001;
const max_id = 0xFEFFFFFF;

pub fn init(gpa: Allocator, socket: os.File) ProxyManager {
    return ProxyManager{
        .gpa = gpa,
        .socket = socket,
        .next_id = min_id,
        .free_list = FreeList.init(gpa, {}),
        .proxy_type_references = EventIdList.init(gpa),
        .mutex = Mutex{},
    };
}

pub fn deinit(self: ProxyManager) void {
    self.free_list.deinit();
    self.proxy_type_references.deinit();
}

pub const GetProxyError = error{IdsExhausted} || Allocator.Error;

pub fn getNewProxy(self: *ProxyManager, comptime Interface: type) GetProxyError!Proxy {
    self.mutex.lock();
    defer self.mutex.unlock();
    return Proxy{
        .gpa = self.gpa,
        .id = self.free_list.removeOrNull() orelse id: {
            if (self.next_id > max_id)
                return error.IdsExhausted;
            defer self.next_id += 1;
            const id = self.next_id;
            try self.proxy_type_references.ensureTotalCapacity(id + 1);
            self.proxy_type_references.expandToCapacity();
            self.proxy_type_references.items[id] = Interface.event0_index;
            break :id id;
        },
        .event0_index = Interface.event0_index,
        .socket = self.socket,
        .manager = self,
    };
}

pub const DeleteIdError = Allocator.Error;

pub fn deleteId(self: *ProxyManager, id: u32) DeleteIdError!void {
    self.mutex.lock();
    defer self.mutex.unlock();
    if (id == self.next_id - 1) {
        self.next_id = id;
    } else {
        try self.free_list.add(id);
    }
}

const ProxyManager = @This();

const std = @import("std");
const os = @import("os");
const Proxy = @import("Proxy.zig");
const Allocator = std.mem.Allocator;
const Mutex = std.Thread.Mutex;
const EventIdList = std.ArrayList(u32);
const FreeList = std.PriorityQueue(u32, void, struct {
    pub fn lessThan(_: void, a: u32, b: u32) std.math.Order {
        return std.math.order(a, b);
    }
}.lessThan);
