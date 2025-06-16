const std = @import("std");
const types = @import("types.zig");
const MqttError = @import("error.zig").MqttError;

const activeTag = std.meta.activeTag;
const testing = std.testing;
const Utf8View = std.unicode.Utf8View;

pub inline fn read_u8_idx(data: []const u8, idx: *usize) u8 {
    idx.* += 1;
    return data[0];
}

// Big Endian
pub inline fn read_u16(data: []const u8) u16 {
    const high = @as(u16, data[0]);
    const low = @as(u16, data[1]);
    return (high << 8) | low;
}

pub inline fn read_u16_idx(data: []const u8, idx: *usize) u16 {
    idx.* += 2;
    return read_u16(data);
}

pub inline fn read_bytes_idx(data: []const u8, idx: *usize) MqttError![]const u8 {
    const len = @as(usize, read_u16_idx(data, idx));
    if (2 + len > data.len) {
        return error.ReadBufNotEnough;
    }
    idx.* += len;
    return data[2 .. 2 + len];
}

pub inline fn read_string_idx(data: []const u8, idx: *usize) MqttError!Utf8View {
    const content = try read_bytes_idx(data, idx);
    // TODO: use more efficient SIMD version here (current is SIMD version)
    if (!std.unicode.utf8ValidateSlice(content)) {
        return error.InvalidString;
    }
    return Utf8View.initUnchecked(content);
}

pub inline fn write_u8_idx(data: []u8, idx: *usize, value: u8) void {
    data[idx.*] = value;
    idx.* += 1;
}

// Big Endian
pub inline fn write_u16(data: []u8, idx: usize, value: u16) void {
    const low = value & 0xFF;
    const high = value >> 8;
    data[idx] = @intCast(high);
    data[idx + 1] = @intCast(low);
}

pub inline fn write_u16_idx(data: []u8, idx: *usize, value: u16) void {
    write_u16(data, idx.*, value);
    idx.* += 2;
}

pub inline fn write_bytes(data: []u8, idx: *usize, value: []const u8) void {
    @memcpy(data[idx.* .. idx.* + value.len], value);
    idx.* += value.len;
}

pub inline fn write_bytes_idx(data: []u8, idx: *usize, value: []const u8) void {
    write_u16_idx(data, idx, @intCast(value.len));
    @memcpy(data[idx.* .. idx.* + value.len], value);
    idx.* += value.len;
}

pub inline fn write_var_int_idx(data: []u8, idx: *usize, const_len: usize) void {
    var len = const_len;
    while (true) {
        var byte: u8 = @intCast(len % 128);
        len /= 128;
        if (len > 0) {
            byte |= 128;
        }
        write_u8_idx(data, idx, byte);
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

pub fn encode_packet(
    comptime T: type,
    packet: T,
    control_byte: u8,
    remaining_len: usize,
    data: []u8,
    idx: *usize,
) void {
    // encode header
    write_u8_idx(data, idx, control_byte);
    write_var_int_idx(data, idx, remaining_len);
    packet.encode(data, idx);
}

/// This function is copied from `std.meta.eql`.
pub fn eql(a: anytype, b: @TypeOf(a)) bool {
    const T = @TypeOf(a);

    switch (@typeInfo(T)) {
        .@"struct" => |info| {
            // Special case: ArrayList
            inline for (info.fields) |field_info| {
                switch (@typeInfo(field_info.type)) {
                    .pointer => |p| {
                        if (T == std.ArrayList(p.child)) {
                            return eql(a.items, b.items);
                        }
                    },
                    else => {},
                }
            }

            inline for (info.fields) |field_info| {
                if (!eql(@field(a, field_info.name), @field(b, field_info.name))) return false;
            }
            return true;
        },
        .error_union => {
            if (a) |a_p| {
                if (b) |b_p| return eql(a_p, b_p) else |_| return false;
            } else |a_e| {
                if (b) |_| return false else |b_e| return a_e == b_e;
            }
        },
        .@"union" => |info| {
            if (info.tag_type) |UnionTag| {
                const tag_a = activeTag(a);
                const tag_b = activeTag(b);
                if (tag_a != tag_b) return false;

                inline for (info.fields) |field_info| {
                    if (@field(UnionTag, field_info.name) == tag_a) {
                        return eql(@field(a, field_info.name), @field(b, field_info.name));
                    }
                }
                return false;
            }

            @compileError("cannot compare untagged union type " ++ @typeName(T));
        },
        .array => {
            if (a.len != b.len) return false;
            for (a, 0..) |e, i|
                if (!eql(e, b[i])) return false;
            return true;
        },
        .vector => |info| {
            var i: usize = 0;
            while (i < info.len) : (i += 1) {
                if (!eql(a[i], b[i])) return false;
            }
            return true;
        },
        .pointer => |info| {
            return switch (info.size) {
                .one, .many, .c => a == b,
                .slice => {
                    // Compare the content
                    if (a.len != b.len) return false;
                    for (a, 0..) |a_item, i| {
                        const b_item = b[i];
                        if (!eql(a_item, b_item)) return false;
                    }
                    return true;
                },
            };
        },
        .optional => {
            if (a == null and b == null) return true;
            if (a == null or b == null) return false;
            return eql(a.?, b.?);
        },
        else => return a == b,
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
        const data, const expected_var_int, const expected_bytes = case;
        const var_int, const bytes = (try decode_var_int(data)).?;
        try testing.expect(var_int == expected_var_int);
        try testing.expect(bytes == expected_bytes);
    }

    try testing.expect((try decode_var_int(&.{ 0xff, 0xff, 0xff })) == null);
    try testing.expect(decode_var_int(&.{ 0xff, 0xff, 0xff, 0xff }) == error.InvalidVarByteInt);
}
