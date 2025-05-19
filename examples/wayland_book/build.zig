const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const wayland_client = b.dependency("wayland_client", .{
        .target = target,
        .optimize = optimize,
        .extensions = @as([]const std.Build.LazyPath, &.{b.path("xdg-shell.xml")}),
    });
    const wlkb = b.dependency("wlkb", .{
        .target = target,
        .optimize = optimize,
    });

    const exe = b.addExecutable(.{
        .name = "wayland_book",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "wayland_client", .module = wayland_client.module("wayland_client") },
                .{ .name = "wlkb", .module = wlkb.module("wlkb") },
            },
        }),
    });

    exe.root_module.addImport("wlkb", wlkb.module("wlkb"));

    b.installArtifact(exe);

    const run_exe = b.addRunArtifact(exe);
    const run_step = b.step("run", "Run the exe");
    run_step.dependOn(&run_exe.step);
}
