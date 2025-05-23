const std = @import("std");
const wl = @import("protocol");
const shared = @import("shared");
const s = shared.serializer_utils;
const roundup4 = s.roundup4;
const Socket = shared.Socket;
const ProxyManager = shared.ProxyManager;
const Proxy = shared.Proxy;
const Fixed = shared.Fixed;
const Header = s.Header;
const Array = s.Array;
const String = s.String;
const Fd = std.posix.fd_t;

threadlocal var scratch_buf = [_]u8{0} ** std.math.maxInt(u16) + 8;
threadlocal var buf = &scratch_buf;
threadlocal var fd_buf: []Fd = undefined;
threadlocal var header: Header = undefined;

pub fn parseEvent(socket: Socket, proxy_manager: *const ProxyManager) wl.Event {
    _ = try socket.peek(std.mem.asBytes(&header));
    const ev_idx = proxy_manager.proxy_type_references[header.object] + header.opcode;
    const field = @typeInfo(wl.Event).@"union".fields[ev_idx];
    const fd_count = countFds(field.type);
    var fds: [fd_count]Fd = undefined;
    var len = try socket.recieveWithFds(&fds, buf);
    while (len < header.length) {
        len += try socket.read(buf[len..]);
    }
    buf = &scratch_buf;
    fd_buf = &fds;
    return @unionInit(wl.Event, field.name, deserailize(field.type, header.object));
}

fn deserailize(comptime T: type, object: u32) T {
    var value: T = undefined;
    inline for (@typeInfo(T).@"struct".fields) |field| {
        if (comptime std.mem.eql(u8, field.name, "self")) {
            value.self = T{ .proxy = Proxy{ .id = object } };
            continue;
        }
        @field(value, field.name) = readField(T);
    }
    return value;
}

fn countFds(comptime T: type) usize {
    comptime var count: usize = 0;
    inline for (@typeInfo(T).@"struct".fields) |field| {
        if (field.type == Fd) count += 1;
    }
    return count;
}

fn readField(comptime T: type) T {
    return switch (T) {
        u32 => readUInt(),
        i32 => readInt(),
        Fixed => readFixed(),
        Array => readArray(),
        String => readString(),
        Fd => readFd(),
        else => readAny(T),
    };
}

fn readAny(comptime T: type) T {
    return switch (@typeInfo(T)) {
        .@"enum" => @enumFromInt(readUInt()),
        .@"struct" => |st| switch (st.layout) {
            .@"packed" => readBitfield(T),
            else => readObject(T),
        },
        .optional => readNullableObject(T),
        else => unreachable,
    };
}

fn readUInt() u32 {
    defer buf = buf[4..];
    return std.mem.bytesToValue(u32, buf[0..4]);
}

fn readInt() i32 {
    defer buf = buf[4..];
    return std.mem.bytesToValue(i32, buf[0..4]);
}

fn readFixed() Fixed {
    return Fixed{ .data = readInt() };
}

fn readArray() Array {
    const len = readUInt();
    const padded_len = roundup4(len);
    defer buf = buf[padded_len..];
    return buf[0..len];
}

fn readString() String {
    const len = readUInt();
    const padded_len = roundup4(len);
    defer buf = buf[padded_len..];
    return buf[0 .. len - 1];
}

fn readObject(comptime Interface: type) Interface {
    return Interface{ .proxy = Proxy{ .id = readUInt() } };
}

fn readNullableObject(comptime Interface: type) ?Interface {
    const id = readUInt();
    return if (id == 0) null else Interface{ .proxy = Proxy{ .id = id } };
}

fn readEnum(comptime E: type) E {
    return @enumFromInt(readUInt());
}

fn readBitfield(comptime T: type) T {
    return @bitCast(readUInt());
}

fn readFd() Fd {
    defer fd_buf = fd_buf[1..];
    return fd_buf[0];
}
