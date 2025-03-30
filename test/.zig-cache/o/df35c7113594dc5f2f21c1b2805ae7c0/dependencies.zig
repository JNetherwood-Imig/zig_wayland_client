pub const packages = struct {
    pub const @".." = struct {
        pub const build_root = "/home/jackson/Dev/zig/wayland_protocols/test/..";
        pub const build_zig = @import("..");
        pub const deps: []const struct { []const u8, []const u8 } = &.{
            .{ "scanner", "../scanner" },
        };
    };
    pub const @"../scanner" = struct {
        pub const build_root = "/home/jackson/Dev/zig/wayland_protocols/test/../scanner";
        pub const build_zig = @import("../scanner");
        pub const deps: []const struct { []const u8, []const u8 } = &.{
        };
    };
};

pub const root_deps: []const struct { []const u8, []const u8 } = &.{
    .{ "wayland_protocols", ".." },
};
