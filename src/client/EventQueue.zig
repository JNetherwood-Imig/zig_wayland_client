const std = @import("std");
const Self = @This();
const wl = @import("client_protocol");

const Queue = std.fifo.LinearFifo(wl.Event, .{ .Static = 64 });

queue: Queue,
mutex: std.Thread.Mutex,
