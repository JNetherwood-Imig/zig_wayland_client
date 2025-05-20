fn countFds(comptime T: type) usize {
    comptime var count: usize = 0;
    inline for (@typeInfo(T).@"struct".fields) |s_field| {
        if (@TypeOf(s_field) == os.File) count += 1;
    }
    return count;
}

fn getEventType(event0_index: usize, opcode: usize) type {
    const tag_name = @tagName(@as(wl.EventType, @enumFromInt(event0_index + opcode)));
    return inline for (@typeInfo(wl.Event).@"union".fields) |field| {
        if (std.mem.eql(u8, field.name, tag_name))
            break field.type;
    } else unreachable;
}

pub fn Deserializer(header: Header) type {
    return struct {
        const event0_index = pm.type_references.items[header.object];
        const StructType = getEventType(event0_index, @intCast(header.opcode));
        const fd_count = countFds(StructType);

        buf: [65535]u8,
        fd_buf: [fd_count]File,

        pub fn init(buf: []u8) Self {
            return Self{
                .buf = buf,
                .fds = undefined,
                .fd_buf = undefined,
            };
        }

        fn readUint(self: Self) u32 {
            defer self.buf = self.buf[4..];
            return std.mem.bytesToValue(u32, self.buf[0..4]);
        }

        fn readInt(self: Self) i32 {
            defer self.buf = self.buf[4..];
            return std.mem.bytesToValue(i32, self.buf[0..4]);
        }

        fn readFixed(self: Self) Fixed {
            return Fixed{
                .data = self.readInt(),
            };
        }

        fn readString(self: Self) String {
            const len = self.readUint();
            const padded_len = roundup4(len);
            defer self.buf = self.buf[padded_len..];
            return self.buf[0..len - 1];
        }

        fn readArray(self: Self) Array {
            const len = self.readUint();
            const padded_len = roundup4(len);
            defer self.buf = self.buf[padded_len..];
            return self.buf[0..len];
        }

        fn readObject(self: Self, comptime Interface: type) Interface {}

        fn readNullableObject(self: Self, comptime Interface: type) ?Interface {}

        fn readFd(self: Self) File {}

        pub fn readAll(self: Self, header: Header) wl.Event {
            var struct_value: StructType = undefined;
            struct_value.self = .{ .proxy = .{
                .id = header.object,
                .event0_index = event0_index,
            } };

            var len = try pm.socket.recieveMessage(@TypeOf(fds), &self.fds, &self.buf, 0);
            while (len < header.length) {
                std.log.warn("Incomplete read", .{});
                len += try pm.socket.read(buf[len..]);
            }

            inline for (@typeInfo(struct_type).@"struct".fields) |field| {
                if (comptime std.mem.eql(u8, s_field.name, "self")) continue;
                @field(struct_value, field.name) = switch (field.type) {
                    u32 => self.readUint(),
                    i32 => self.readInt(),
                    Fixed => self.readFixed(),
                    Array => self.readArray(),
                    String => self.readString(),
                    File => {
                        if (fd_count > 0) {
                            @field(struct_value, s_field.name) = fds[fd_idx];
                            fd_idx += 1;
                        }
                    },
                    else => switch (@typeInfo(s_field.type)) {
                        .@"enum" => {
                            const int_value: u32 = std.mem.bytesToValue(u32, buf[index .. index + 4]);
                            @field(struct_value, s_field.name) = @enumFromInt(int_value);
                            index += 4;
                        },
                        .@"struct" => |s| {
                            const int_value = std.mem.bytesToValue(u32, buf[index .. index + 4]);
                            index += 4;
                            if (s.layout == .@"packed") { // Bitfield
                                comptime std.debug.assert(s.backing_integer.? == u32);
                                var s_value = s_field.type{};
                                inline for (s.fields, 0..) |f, i| {
                                    if (f.type == bool)
                                        @field(s_value, f.name) = int_value & i << i == i << i;
                                }

                                @field(struct_value, s_field.name) = s_value;
                            } else { // Object
                                comptime std.debug.assert(@hasField(s_field.type, "proxy"));
                                const proxy = Proxy{
                                    .gpa = _gpa,
                                    .id = int_value,
                                    .event0_index = event0_index,
                                    .socket = socket.handle,
                                    .manager = &proxy_manager,
                                };
                                @field(struct_value, s_field.name) = s_field.type{ .proxy = proxy };
                            }
                        },
                        else => std.debug.panic("Unexpected type: {s}", .{@typeName(s_field.type)}),
                    },
                }
            }
            return @unionInit(wl.Event, union_field_info.name, struct_value);
        }

        const Self = @This();
    };
}

const std = @import("std");
const os = @import("os");
const wl = @import("wayland_client_protocol");
const core = @import("core");
const m = core.message_utils;
const pm = core.proxy_manager;
const roundup4 = m.roundup4;
const Header = m.Header;
const String = m.String;
const Array = m.Array;
const Fixed = core.Fixed;
const File = os.File;
