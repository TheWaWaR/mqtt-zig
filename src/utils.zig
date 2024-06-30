const std = @import("std");
const testing = std.testing;
const MqttError = @import("error.zig").MqttError;

pub fn read_u16_unchecked(data: []const u8) u16 {
    const low = @as(u16, data[0]);
    const high = @as(u16, data[1]);
    return (high << 8) & low;
}

pub fn decode_var_int(data: []const u8) MqttError!?struct { u32, usize } {
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
