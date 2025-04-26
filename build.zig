const std = @import("std");
const LazyPath = std.Build.LazyPath;

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const scannner_dep = b.dependency("scanner", .{
        .target = target,
        .optimize = optimize,
    });

    const scanner = scannner_dep.artifact("scanner");

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

    const client_mod = b.addModule("client", .{
        .root_source_file = b.path("src/client.zig"),
        .target = target,
        .optimize = optimize,
    });

    const client_protocol = generateClient(b, core_path, files, dirs, scanner);
    client_mod.addAnonymousImport(
        "client_protocol",
        .{ .root_source_file = client_protocol },
    );

    const server_mod = b.addModule("server", .{
        .root_source_file = b.path("src/server.zig"),
        .target = target,
        .optimize = optimize,
    });

    const server_protocol = generateServer(b, core_path, files, dirs, scanner);
    server_mod.addAnonymousImport(
        "server_protocol",
        .{ .root_source_file = server_protocol },
    );

    const client_tests = b.addTest(.{
        .root_module = client_mod,
    });
    const run_client_tests = b.addRunArtifact(client_tests);

    const server_tests = b.addTest(.{
        .root_module = server_mod,
    });
    const run_server_tests = b.addRunArtifact(server_tests);

    const run_tests = b.step("test", "Run unit tests");
    run_tests.dependOn(&run_client_tests.step);
    run_tests.dependOn(&run_server_tests.step);
}

fn generateClient(
    b: *std.Build,
    core_path: ?LazyPath,
    files: ?[]const LazyPath,
    dirs: ?[]const LazyPath,
    scanner: *std.Build.Step.Compile,
) LazyPath {
    const generate_files = b.addWriteFiles();

    const run_scanner = b.addRunArtifact(scanner);
    run_scanner.setCwd(generate_files.getDirectory());
    run_scanner.addArg("client");
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
    _ = write_files.addCopyDirectory(b.path("src/client"), "client", .{});
    _ = write_files.addCopyDirectory(b.path("src/common"), "common", .{});
    _ = write_files.addCopyDirectory(b.path("src/os"), "os", .{});
    _ = write_files.addCopyFile(b.path("src/os.zig"), "os.zig");
    return write_files.addCopyFile(generated, "client_protocol.zig");
}

fn generateServer(
    b: *std.Build,
    core_path: ?LazyPath,
    files: ?[]const LazyPath,
    dirs: ?[]const LazyPath,
    scanner: *std.Build.Step.Compile,
) LazyPath {
    const generate_files = b.addWriteFiles();

    const run_scanner = b.addRunArtifact(scanner);
    run_scanner.setCwd(generate_files.getDirectory());
    run_scanner.addArg("server");
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
    _ = write_files.addCopyDirectory(b.path("src/server"), "server", .{});
    _ = write_files.addCopyDirectory(b.path("src/common"), "common", .{});
    return write_files.addCopyFile(generated, "server_protocol.zig");
}
