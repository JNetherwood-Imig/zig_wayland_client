const min_id = 0x00000002;
const max_id = 0xFEFFFFFF;

var next_id: u32 = min_id;
var mutex = Mutex{};

var alloc: Allocator = undefined;
var free_list: FreeList = undefined;
pub var socket: os.File = undefined;
pub var type_references: EventIdList = undefined;

pub fn init(gpa: Allocator, sock: os.File) void {
    alloc = gpa;
    socket = sock;
    free_list = FreeList.init(gpa, {});
    type_references = EventIdList.init(gpa);
}

pub fn deinit() void {
    free_list.deinit();
    type_references.deinit();
}

pub const GetProxyError = error{IdsExhausted} || Allocator.Error;

pub fn getNewProxy(comptime Interface: type) GetProxyError!Proxy {
    mutex.lock();
    defer mutex.unlock();
    return Proxy{
        .gpa = alloc,
        .id = id: {
            if (free_list.removeOrNull()) |id| {
                type_references.items[id] = Interface.event0_index;
                break :id id;
            }
            break :id null;
        } orelse id: {
            if (next_id > max_id)
                return error.IdsExhausted;
            defer next_id += 1;
            const id = next_id;
            try type_references.ensureTotalCapacity(id + 1);
            type_references.expandToCapacity();
            type_references.items[id] = Interface.event0_index;
            break :id id;
        },
        .event0_index = Interface.event0_index,
        .socket = socket,
    };
}

pub const DeleteIdError = Allocator.Error;

pub fn deleteId(id: u32) DeleteIdError!void {
    mutex.lock();
    defer mutex.unlock();
    try free_list.add(id);
}

const std = @import("std");
const os = @import("os");
const Proxy = @import("Proxy.zig");
const Allocator = std.mem.Allocator;
const Mutex = std.Thread.Mutex;
const EventIdList = std.ArrayList(usize);
const FreeList = std.PriorityQueue(u32, void, struct {
    pub fn lessThan(_: void, a: u32, b: u32) std.math.Order {
        return std.math.order(a, b);
    }
}.lessThan);
