const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const scanner = b.addExecutable(.{
        .name = "scanner",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    b.installArtifact(scanner);

    const run_exe = b.addRunArtifact(scanner);
    run_exe.addArg("-f/usr/share/wayland/wayland.xml");
    run_exe.addArg("-f/usr/share/wayland-protocols/stable/xdg-shell/xdg-shell.xml");

    const run_step = b.step("run", "Run the application");
    run_step.dependOn(&run_exe.step);
}
