const std = @import("std");
const LazyPath = std.Build.LazyPath;

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const scanner = b.addExecutable(.{
        .name = "scanner",
        .target = target,
        .optimize = optimize,
        .root_source_file = b.path("scanner/scanner.zig"),
    });

    const generate_files = b.addWriteFiles();

    const run_scanner = b.addRunArtifact(scanner);
    run_scanner.setCwd(generate_files.getDirectory());
    const generated = run_scanner.addPrefixedOutputFileArg("-o", "generated.zig");

    const extensions = b.option(
        []const LazyPath,
        "extensions",
        "A list of paths to valid wayland protocol extension xml files.",
    );

    const wayland_xml_path = b.option(
        LazyPath,
        "wayland_xml_path",
        "Override path to the wayland.xml file.",
    );

    if (wayland_xml_path) |path| {
        run_scanner.addPrefixedFileArg("-o", path);
    }

    if (extensions) |e| for (e) |extension| {
        run_scanner.addPrefixedFileArg("-e", extension);
    };

    const write_files = b.addWriteFiles();
    const output = write_files.addCopyFile(generated, "client_protocol.zig");
    _ = write_files.addCopyDirectory(generate_files.getDirectory(), "", .{});

    const os = b.createModule(.{
        .root_source_file = b.path("src/os.zig"),
        .target = target,
        .optimize = optimize,
    });

    const shared = b.createModule(.{
        .root_source_file = b.path("src/shared.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "os", .module = os },
        },
    });

    const wayland_client_protocol = b.createModule(.{
        .root_source_file = output,
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "os", .module = os },
            .{ .name = "shared", .module = shared },
        },
    });

    const wayland_client = b.addModule("wayland_client", .{
        .root_source_file = b.path("src/wayland_client.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "os", .module = os },
            .{ .name = "shared", .module = shared },
            .{ .name = "wayland_client_protocol", .module = wayland_client_protocol },
        },
    });

    const os_test = b.addTest(.{
        .root_module = os,
        .target = target,
        .optimize = optimize,
        .use_llvm = false,
        .use_lld = false,
    });

    const shared_test = b.addTest(.{
        .root_module = shared,
        .target = target,
        .optimize = optimize,
        .use_llvm = false,
        .use_lld = false,
    });

    const wayland_client_test = b.addTest(.{
        .root_module = wayland_client,
        .target = target,
        .optimize = optimize,
        .use_llvm = false,
        .use_lld = false,
    });

    const run_os_test = b.addRunArtifact(os_test);
    const run_shared_test = b.addRunArtifact(shared_test);
    const run_wayland_client_test = b.addRunArtifact(wayland_client_test);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_os_test.step);
    test_step.dependOn(&run_shared_test.step);
    test_step.dependOn(&run_wayland_client_test.step);
}
