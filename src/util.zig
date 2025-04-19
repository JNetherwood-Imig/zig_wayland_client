pub const posix = @import("util/posix.zig");

pub const io = @import("util/io.zig");

pub const gpa = struct {
    var debug_gpa = heap.GeneralPurposeAllocator(.{}){};
    const debug_allocator = debug_gpa.allocator();
    const release_allocator = heap.smp_allocator;

    pub const allocator = if (mode == .ReleaseFast)
        release_allocator
    else
        debug_allocator;

    pub inline fn deinit() void {
        if (mode != .ReleaseFast) _ = debug_gpa.deinit();
    }
};

const heap = @import("std").heap;
const mode = @import("builtin").mode;
