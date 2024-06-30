const std = @import("std");
const MqttError = @import("error.zig").MqttError;

const testing = std.testing;
const Utf8View = std.unicode.Utf8View;

pub inline fn read_u8_idx(data: []const u8, idx: *usize) u8 {
    idx.* += 1;
    return data[0];
}

pub inline fn read_u16(data: []const u8) u16 {
    const low = @as(u16, data[0]);
    const high = @as(u16, data[1]);
    return (high << 8) & low;
}

pub inline fn read_u16_idx(data: []const u8, idx: *usize) u16 {
    idx.* += 2;
    return read_u16(data);
}

pub inline fn read_bytes_idx(data: []const u8, idx: *usize) []const u8 {
    const len = @as(usize, read_u16_idx(data, idx));
    idx.* += len;
    return data[2 .. 2 + len];
}

pub inline fn read_string_idx(data: []const u8, idx: *usize) MqttError!Utf8View {
    const content = read_bytes_idx(data, idx);
    // TODO: use more efficient SIMD version here (current is SIMD version)
    if (!std.unicode.utf8ValidateSlice(content)) {
        return error.InvalidString;
    }
    return Utf8View.initUnchecked(content);
}

pub inline fn write_u8_idx(data: []u8, value: u8, idx: *usize) void {
    data[idx.*] = value;
    idx.* += 1;
}

pub inline fn write_u16_idx(data: []u8, value: u16, idx: *usize) void {
    const low = value & 0xFF00;
    const high = value >> 8;
    data[idx.*] = @intCast(low);
    data[idx.* + 1] = @intCast(high);
    idx.* += 2;
}

pub inline fn write_bytes_idx(data: []u8, value: []const u8, idx: *usize) void {
    write_u16_idx(data, @intCast(value.len), idx);
    @memcpy(data[idx.* .. idx.* + value.len], value);
    idx.* += value.len;
}

pub inline fn write_var_int_idx(data: []u8, len: usize, idx: *usize) void {
    while (true) {
        var byte = @as(u8, len % 128);
        len /= 128;
        if (len > 0) {
            byte |= 128;
        }
        write_u8_idx(data, byte, idx);
        if (len == 0) {
            break;
        }
    }
}

/// Decode a variable byte integer (4 bytes max)
pub inline fn decode_var_int(data: []const u8) MqttError!?struct { u32, usize } {
    var var_int: u32 = 0;
    var i: usize = 0;
    while (i < data.len) {
        const byte = data[i];
        var_int |= (@as(u32, byte) & 0x7F) << @as(u5, @intCast(7 * i));
        if (byte & 0x80 == 0) {
            break;
        } else if (i < 3) {
            i += 1;
        } else {
            return error.InvalidVarByteInt;
        }
    }
    if (i == data.len) {
        // EOF reached
        return null;
    }
    return .{ var_int, i + 1 };
}

/// Return the encoded size of the variable byte integer.
pub inline fn var_int_len(value: usize) MqttError!usize {
    if (value < 128) {
        return 1;
    } else if (value < 16384) {
        return 2;
    } else if (value < 2097152) {
        return 3;
    } else if (value < 268435456) {
        return 4;
    } else {
        error.InvalidVarByteInt;
    }
}

/// Return the packet total encoded length by a given remaining length.
pub inline fn total_length(remaining_len: usize) MqttError!usize {
    if (remaining_len < 128) {
        return 2 + remaining_len;
    } else if (remaining_len < 16384) {
        return 3 + remaining_len;
    } else if (remaining_len < 2097152) {
        return 4 + remaining_len;
    } else if (remaining_len < 268435456) {
        return 5 + remaining_len;
    } else {
        return error.InvalidVarByteInt;
    }
}

/// Calculate remaining length by given total length (the total length MUST be
/// valid value).
pub inline fn remaining_length(total_len: usize) usize {
    return total_len - header_length(total_len);
}

/// Calculate header length by given total length (the total length MUST be
/// valid value).
pub inline fn header_length(total_len: usize) usize {
    if (total_len < 128 + 2) {
        return 2;
    } else if (total_len < 16384 + 3) {
        return 3;
    } else if (total_len < 2097152 + 4) {
        return 4;
    } else {
        return 5;
    }
}

test "decode var int" {
    const cases = [_]struct { []const u8, u32, usize }{
        .{ &.{ 0xff, 0xff, 0xff, 0x7f }, 268435455, 4 },
        .{ &.{ 0x80, 0x80, 0x80, 0x01 }, 2097152, 4 },
        .{ &.{ 0xff, 0xff, 0x7f }, 2097151, 3 },
        .{ &.{ 0x80, 0x80, 0x01 }, 16384, 3 },
        .{ &.{ 0xff, 0x7f }, 16383, 2 },
        .{ &.{ 0x80, 0x01 }, 128, 2 },
        .{ &.{0x7f}, 127, 1 },
        .{ &.{0x00}, 0, 1 },
    };
    for (cases) |case| {
        const data = case[0];
        const var_int = case[1];
        const bytes = case[2];
        const result = (try decode_var_int(data)).?;
        try testing.expect(result[0] == var_int);
        try testing.expect(result[1] == bytes);
    }

    try testing.expect((try decode_var_int(&.{ 0xff, 0xff, 0xff })) == null);
    try testing.expect(decode_var_int(&.{ 0xff, 0xff, 0xff, 0xff }) == error.InvalidVarByteInt);
}
