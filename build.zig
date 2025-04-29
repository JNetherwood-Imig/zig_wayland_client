const std = @import("std");
const LazyPath = std.Build.LazyPath;

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const scanner = b.dependency("scanner", .{
        .target = target,
        .optimize = optimize,
    }).artifact("scanner");

    const files = b.option(
        []const LazyPath,
        "files",
        "A list of wayland protocol xml files.",
    );

    const dirs = b.option(
        []const LazyPath,
        "dirs",
        "A list of directories containing wayland protocol xml files.",
    );

    const core_path = b.option(
        LazyPath,
        "wayland_xml_path",
        "Optional override path to the core wayland.xml file",
    );

    const os = b.createModule(.{
        .root_source_file = b.path("src/os.zig"),
        .target = target,
        .optimize = optimize,
    });

    const common = b.createModule(.{
        .root_source_file = b.path("src/common.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "os", .module = os },
        },
    });

    const os_test = b.addTest(.{ .root_module = os });
    const run_os_test = b.addRunArtifact(os_test);

    const common_test = b.addTest(.{ .root_module = common });
    const run_common_test = b.addRunArtifact(common_test);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_os_test.step);
    test_step.dependOn(&run_common_test.step);

    inline for ([_][]const u8{ "client", "server" }) |mod_name| {
        const generate_files = b.addWriteFiles();

        const run_scanner = b.addRunArtifact(scanner);
        run_scanner.setCwd(generate_files.getDirectory());
        run_scanner.addArg(mod_name);
        const generated = run_scanner.addPrefixedOutputFileArg("-o", "generated.zig");

        if (core_path) |path| run_scanner.addPrefixedFileArg("-c", path);
        if (files) |f| for (f) |file| {
            run_scanner.addPrefixedFileArg("-f", file);
        };

        if (dirs) |d| for (d) |dir| {
            run_scanner.addPrefixedDirectoryArg("-d", dir);
        };

        const write_files = b.addWriteFiles();
        _ = write_files.addCopyDirectory(generate_files.getDirectory(), "", .{});
        const output = write_files.addCopyFile(generated, mod_name ++ "_protocol.zig");

        const protocol_mod = b.createModule(.{
            .root_source_file = output,
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "os", .module = os },
                .{ .name = "common", .module = common },
            },
        });

        const mod = b.addModule(mod_name, .{
            .root_source_file = b.path("src/" ++ mod_name ++ ".zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "os", .module = os },
                .{ .name = "common", .module = common },
                .{ .name = mod_name ++ "_protocol", .module = protocol_mod },
            },
        });

        const mod_test = b.addTest(.{ .root_module = mod });
        const run_test = b.addRunArtifact(mod_test);

        test_step.dependOn(&run_test.step);
    }
}
