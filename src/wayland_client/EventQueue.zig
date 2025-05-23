queue: Queue,
mutex: Thread.Mutex,
condition: Thread.Condition,
cancelled: bool,

pub fn init(gpa: std.mem.Allocator) EventQueue {
    return EventQueue{
        .queue = Queue.init(gpa),
        .mutex = Thread.Mutex{},
        .condition = Thread.Condition{},
        .cancelled = false,
    };
}

pub fn deinit(self: EventQueue) void {
    self.queue.deinit();
}

pub fn emplace(self: *EventQueue, event: wl.Event) !void {
    self.mutex.lock();
    defer self.mutex.unlock();
    try self.queue.writeItem(event);
    self.condition.signal();
}

pub fn wait(self: *EventQueue) ?wl.Event {
    self.mutex.lock();
    defer self.mutex.unlock();

    while (self.queue.count == 0 and !self.cancelled)
        self.condition.wait(&self.mutex);

    return if (self.cancelled) null else self.queue.readItem();
}

pub fn get(self: *EventQueue) ?wl.Event {
    if (self.mutex.tryLock()) {
        defer self.mutex.unlock();
        return self.queue.readItem();
    }
    return null;
}

pub fn cancel(self: *EventQueue) void {
    self.mutex.lock();
    defer self.mutex.unlock();
    self.cancelled = true;
    self.condition.broadcast();
}

const EventQueue = @This();

const std = @import("std");
const wl = @import("protocol");
// FIXME Switch queue to a .Static 64 queue once more advanced synchronization is in place
// which will pause reading until the queue has space
const Queue = std.fifo.LinearFifo(wl.Event, .Dynamic);
const Thread = std.Thread;
