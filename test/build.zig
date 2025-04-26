const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const wayland = b.dependency("wayland", .{
        .dirs = @as([]const std.Build.LazyPath, &.{b.path("protocols/")}),
    });

    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "wayland_client", .module = wayland.module("client") },
        },
    });

    const exe = b.addExecutable(.{
        .name = "test",
        .use_llvm = false,
        .use_lld = false,
        .link_libc = false,
        .root_module = exe_mod,
    });

    b.installArtifact(exe);

    const run_exe = b.addRunArtifact(exe);
    const run_step = b.step("run", "Run the exe");
    run_step.dependOn(&run_exe.step);
}
