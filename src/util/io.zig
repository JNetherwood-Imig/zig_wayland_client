pub inline fn print(comptime text: []const u8) void {
    std.io.getStdOut().writeAll(text) catch return;
}

pub inline fn println(comptime text: []const u8) void {
    std.io.getStdOut().writeAll(text ++ newline) catch return;
}

pub inline fn printf(comptime format: []const u8, args: anytype) void {
    std.io.getStdOut().writer().print(format, args) catch return;
}

pub inline fn printfln(comptime format: []const u8, args: anytype) void {
    std.io.getStdOut().writer().print(format ++ newline, args) catch return;
}

pub inline fn eprint(comptime text: []const u8) void {
    std.Progress.lockStdErr();
    defer std.Progress.unlockStdErr();
    std.io.getStdErr().writeAll(text) catch return;
}

pub inline fn eprintln(comptime text: []const u8) void {
    std.Progress.lockStdErr();
    defer std.Progress.unlockStdErr();
    std.io.getStdErr().writeAll(text ++ newline) catch return;
}

pub inline fn eprintf(comptime format: []const u8, args: anytype) void {
    std.Progress.lockStdErr();
    defer std.Progress.unlockStdErr();
    std.io.getStdErr().writer().print(format, args) catch return;
}

pub inline fn eprintfln(comptime format: []const u8, args: anytype) void {
    std.Progress.lockStdErr();
    defer std.Progress.unlockStdErr();
    std.io.getStdErr().writer().print(format ++ newline, args) catch return;
}

test "io" {
    eprintln("Testing print functions...");

    print("This is a message from print\n");
    println("This is a message from println");
    printf("This is a message from {s}\n", .{"printf"});
    printfln("This is a message from {s}", .{"printfln"});

    eprint("This is a message from eprint\n");
    eprintln("This is a message from eprintln");
    eprintf("This is a message from {s}\n", .{"eprintf"});
    eprintfln("This is a message from {s}", .{"eprintfln"});
}

const std = @import("std");
const builtin = @import("builtin");
const os = builtin.target.os;
const newline = if (os.tag == .windows) "\r\n" else "\n";
