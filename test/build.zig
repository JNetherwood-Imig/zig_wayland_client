const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const files: []const std.Build.LazyPath = &.{
        b.path("wayland.xml"),
        b.path("xdg-shell.xml"),
        b.path("linux-drm-syncobj-v1.xml"),
    };

    const wayland_protocols = b.dependency("wayland_protocols", .{
        .files = files,
    });

    const exe = b.addExecutable(.{
        .name = "test",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "wayland_client", .module = wayland_protocols.module("root") },
            },
        }),
    });

    b.installArtifact(exe);
}
