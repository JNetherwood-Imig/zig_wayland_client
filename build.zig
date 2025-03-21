const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const scannner_dep = b.dependency("scanner", .{
        .target = target,
        .optimize = optimize,
    });

    const scanner = scannner_dep.artifact("scanner");

    const files = b.option(
        []const std.Build.LazyPath,
        "files",
        "A list of wayland protocol xml files.",
    );

    const dirs = b.option(
        []const std.Build.LazyPath,
        "dirs",
        "A list of directories containing wayland protocol xml files.",
    );

    const wf1 = b.addWriteFiles();

    const run_scanner = b.addRunArtifact(scanner);
    run_scanner.setCwd(wf1.getDirectory());
    const generated_src = run_scanner.addPrefixedOutputFileArg("-o", "generated.zig");

    if (files) |f| for (f) |file| {
        run_scanner.addPrefixedFileArg("-f", file);
    };

    if (dirs) |d| for (d) |dir| {
        run_scanner.addPrefixedDirectoryArg("-d", dir);
    };

    const wf2 = b.addWriteFiles();
    _ = wf2.addCopyDirectory(wf1.getDirectory(), "", .{});
    const generated = wf2.addCopyFile(generated_src, "generated.zig");
    _ = wf2.addCopyFile(b.path("src/Display.zig"), "Display.zig");
    _ = wf2.addCopyFile(b.path("src/Object.zig"), "Object.zig");
    _ = wf2.addCopyFile(b.path("src/Fixed.zig"), "Fixed.zig");

    const mod = b.addModule("root", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    mod.addAnonymousImport("generated", .{ .root_source_file = generated });
}
