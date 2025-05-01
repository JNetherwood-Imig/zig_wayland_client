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

    const test_step = b.step("test", "Run unit tests");

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
        const output = write_files.addCopyFile(generated, mod_name ++ "_protocol.zig");
        _ = write_files.addCopyDirectory(generate_files.getDirectory(), "", .{});
        _ = write_files.addCopyFile(b.path("src/os.zig"), "os.zig");
        _ = write_files.addCopyDirectory(b.path("src/os"), "os", .{});
        _ = write_files.addCopyDirectory(b.path("src/common"), "common", .{});
        const mod_file = write_files.addCopyFile(b.path("src/" ++ mod_name ++ ".zig"), mod_name ++ ".zig");
        _ = write_files.addCopyDirectory(b.path("src/" ++ mod_name), mod_name, .{});

        const mod = b.addModule(mod_name, .{
            .root_source_file = mod_file,
            .target = target,
            .optimize = optimize,
        });
        mod.addAnonymousImport(mod_name ++ "_protocol", .{
            .root_source_file = output,
            .target = target,
            .optimize = optimize,
        });

        const mod_test = b.addTest(.{ .root_module = mod });
        const run_test = b.addRunArtifact(mod_test);

        test_step.dependOn(&run_test.step);
    }
}
