const std = @import("std");
const File = std.fs.File;
const builtin = @import("builtin");

const newline = if (builtin.target.os.tag == .windows) "\r\n" else "\n";

pub fn fprint(file: File, comptime text: []const u8) void {
    file.writeAll(text) catch return;
}

test "fprint" {
    fprint(std.io.getStdErr(), "This is a message from fprint\n");
}

pub fn fprintln(file: File, comptime text: []const u8) void {
    file.writeAll(text ++ newline) catch return;
}

test "fprintln" {
    fprintln(std.io.getStdErr(), "This is a test from fprintln");
}

pub fn fprintf(file: File, comptime format: []const u8, args: anytype) void {
    file.writer().print(format, args) catch return;
}

test "fprintf" {
    fprintf(std.io.getStdErr(), "This is a test from {s}\n", .{"fprintf"});
}

pub fn fprintlnf(file: File, comptime format: []const u8, args: anytype) void {
    file.writer().print(format ++ newline, args) catch return;
}

test "fprintlnf" {
    fprintlnf(std.io.getStdErr(), "This is a test from {s}", .{"fprintlnf"});
}

pub fn print(comptime text: []const u8) void {
    std.io.getStdOut().writeAll(text) catch return;
}

test "print" {
    print("This is a test from print\n");
}

pub fn println(comptime text: []const u8) void {
    std.io.getStdOut().writeAll(text ++ newline) catch return;
}

test "println" {
    println("This is a test from println");
}

pub fn printf(comptime format: []const u8, args: anytype) void {
    std.io.getStdOut().writer().print(format, args) catch return;
}

test "printf" {
    printf("This is a test from {s}\n", .{"printf"});
}

pub fn printlnf(comptime format: []const u8, args: anytype) void {
    std.io.getStdOut().writer().print(format ++ newline, args) catch return;
}

test "printlnf" {
    printlnf("This is a test from {s}", .{"printlnf"});
}

pub fn eprint(comptime text: []const u8) void {
    std.Progress.lockStdErr();
    defer std.Progress.unlockStdErr();
    std.io.getStdErr().writeAll(text) catch return;
}

test "eprint" {
    eprint("This is a test from eprint\n");
}

pub fn eprintln(comptime text: []const u8) void {
    std.Progress.lockStdErr();
    defer std.Progress.unlockStdErr();
    std.io.getStdErr().writeAll(text ++ newline) catch return;
}

test "eprintln" {
    eprintln("This is a test from eprintln");
}

pub fn eprintf(comptime format: []const u8, args: anytype) void {
    std.Progress.lockStdErr();
    defer std.Progress.unlockStdErr();
    std.io.getStdErr().writer().print(format, args) catch return;
}

test "eprintf" {
    eprintf("This is a test from {s}\n", .{"eprintf"});
}

pub fn eprintlnf(comptime format: []const u8, args: anytype) void {
    std.Progress.lockStdErr();
    defer std.Progress.unlockStdErr();
    std.io.getStdErr().writer().print(format ++ newline, args) catch return;
}

test "eprintlnf" {
    eprintlnf("This is a test from {s}", .{"eprintlnf"});
}
