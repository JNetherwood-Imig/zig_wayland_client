queue: Queue = Queue.init(),
mutex: Thread.Mutex = .{},
condition: Thread.Condition = .{}, // TODO rename appropriately
cancelled: bool = false,

pub const InitError = error{};

pub fn init() InitError!Self {
    return .{};
}

pub fn deinit(self: Self) void {
    self.queue.deinit();
}

pub fn emplaceEvent(self: *Self, event: wl.Event) void {
    self.mutex.lock();
    defer self.mutex.unlock();
    self.queue.writeItem(event) catch return;
    self.condition.signal();
}

pub fn waitEvent(self: *Self) ?wl.Event {
    self.mutex.lock();
    defer self.mutex.unlock();

    while (self.queue.count == 0 and !self.cancelled)
        self.condition.wait(&self.mutex);

    return if (self.cancelled) null else self.queue.readItem();
}

pub fn getEvent(self: *Self) ?wl.Event {
    if (self.mutex.tryLock()) {
        defer self.mutex.unlock();
        return self.queue.readItem();
    }
    return null;
}

pub fn cancel(self: *Self) void {
    self.mutex.lock();
    defer self.mutex.unlock();
    self.cancelled = true;
    self.condition.broadcast();
}

const Self = @This();

const std = @import("std");
const Thread = std.Thread;
const Queue = std.fifo.LinearFifo(wl.Event, .{ .Static = 64 });
const wl = @import("client_protocol");
