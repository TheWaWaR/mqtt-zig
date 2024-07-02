const std = @import("std");

const types = @import("../types.zig");
const utils = @import("../utils.zig");
const MqttError = @import("../error.zig").MqttError;
const connect = @import("./connect.zig");
const publish = @import("./publish.zig");
const subscribe = @import("./subscribe.zig");

const testing = std.testing;
const Allocator = std.mem.Allocator;

const read_u16 = utils.read_u16;
const write_bytes_idx = utils.write_bytes_idx;
const encode_packet = utils.encode_packet;
const Pid = types.Pid;
const QoS = types.QoS;

const Connect = connect.Connect;
const Connack = connect.Connack;
const Publish = publish.Publish;
const Subscribe = subscribe.Subscribe;
const Suback = subscribe.Suback;
const Unsubscribe = subscribe.Unsubscribe;

/// MQTT v3.x packet type variant, without the associated data.
pub const PacketType = enum {
    connect,
    connack,
    publish,
    puback,
    pubrec,
    pubrel,
    pubcomp,
    subscribe,
    suback,
    unsubscribe,
    unsuback,
    pingreq,
    pingresp,
    disconnect,
};

/// MQTT v3.x packet types.
pub const Packet = union(PacketType) {
    /// [MQTT 3.1](http://docs.oasis-open.org/mqtt/mqtt/v3.1.1/os/mqtt-v3.1.1-os.html#_Toc398718028)
    connect: Connect,
    /// [MQTT 3.2](http://docs.oasis-open.org/mqtt/mqtt/v3.1.1/os/mqtt-v3.1.1-os.html#_Toc398718033)
    connack: Connack,
    /// [MQTT 3.3](http://docs.oasis-open.org/mqtt/mqtt/v3.1.1/os/mqtt-v3.1.1-os.html#_Toc398718037)
    publish: Publish,
    /// [MQTT 3.4](http://docs.oasis-open.org/mqtt/mqtt/v3.1.1/os/mqtt-v3.1.1-os.html#_Toc398718043)
    puback: Pid,
    /// [MQTT 3.5](http://docs.oasis-open.org/mqtt/mqtt/v3.1.1/os/mqtt-v3.1.1-os.html#_Toc398718048)
    pubrec: Pid,
    /// [MQTT 3.6](http://docs.oasis-open.org/mqtt/mqtt/v3.1.1/os/mqtt-v3.1.1-os.html#_Toc398718053)
    pubrel: Pid,
    /// [MQTT 3.7](http://docs.oasis-open.org/mqtt/mqtt/v3.1.1/os/mqtt-v3.1.1-os.html#_Toc398718058)
    pubcomp: Pid,
    /// [MQTT 3.8](http://docs.oasis-open.org/mqtt/mqtt/v3.1.1/os/mqtt-v3.1.1-os.html#_Toc398718063)
    subscribe: Subscribe,
    /// [MQTT 3.9](http://docs.oasis-open.org/mqtt/mqtt/v3.1.1/os/mqtt-v3.1.1-os.html#_Toc398718068)
    suback: Suback,
    /// [MQTT 3.10](http://docs.oasis-open.org/mqtt/mqtt/v3.1.1/os/mqtt-v3.1.1-os.html#_Toc398718072)
    unsubscribe: Unsubscribe,
    /// [MQTT 3.11](http://docs.oasis-open.org/mqtt/mqtt/v3.1.1/os/mqtt-v3.1.1-os.html#_Toc398718077)
    unsuback: Pid,
    /// [MQTT 3.12](http://docs.oasis-open.org/mqtt/mqtt/v3.1.1/os/mqtt-v3.1.1-os.html#_Toc398718081)
    pingreq,
    /// [MQTT 3.13](http://docs.oasis-open.org/mqtt/mqtt/v3.1.1/os/mqtt-v3.1.1-os.html#_Toc398718086)
    pingresp,
    /// [MQTT 3.14](http://docs.oasis-open.org/mqtt/mqtt/v3.1.1/os/mqtt-v3.1.1-os.html#_Toc398718090)
    disconnect,

    /// Decode a packet from some bytes. If not enough bytes to decode a packet,
    /// it will return `null`.
    ///
    /// If passing `allocator`, this function will alloc memory for inner
    /// dynamic data structure, otherwise inner dynamic data structure will all
    /// reference `data` argument (no heap allocation).
    pub fn decode(
        data: []const u8,
        header: Header,
        allocator_opt: ?Allocator,
    ) MqttError!?struct { Packet, usize } {
        if (data.len < header.remaining_len) {
            return null;
        }
        var size: usize = 0;
        const packet: Packet = switch (header.typ) {
            .pingreq => .pingreq,
            .pingresp => .pingresp,
            .disconnect => .disconnect,
            .connect => blk: {
                const result = try Connect.decode(data, header, allocator_opt);
                size = result[1];
                break :blk .{ .connect = result[0] };
            },
            .connack => blk: {
                const result = try Connack.decode(data);
                size = result[1];
                break :blk .{ .connack = result[0] };
            },
            .publish => blk: {
                const result = try Publish.decode(data, header, allocator_opt);
                size = result[1];
                break :blk .{ .publish = result[0] };
            },
            .puback => blk: {
                size = 2;
                const pid = try Pid.try_from(read_u16(data));
                break :blk .{ .puback = pid };
            },
            .pubrec => blk: {
                size = 2;
                const pid = try Pid.try_from(read_u16(data));
                break :blk .{ .pubrec = pid };
            },
            .pubrel => blk: {
                size = 2;
                const pid = try Pid.try_from(read_u16(data));
                break :blk .{ .pubrel = pid };
            },
            .pubcomp => blk: {
                size = 2;
                const pid = try Pid.try_from(read_u16(data));
                break :blk .{ .pubcomp = pid };
            },
            .subscribe => blk: {
                const result = try Subscribe.decode(data, header);
                size = result[1];
                break :blk .{ .subscribe = result[0] };
            },
            .suback => blk: {
                const result = try Suback.decode(data, header);
                size = result[1];
                break :blk .{ .suback = result[0] };
            },
            .unsubscribe => blk: {
                const result = try Unsubscribe.decode(data, header);
                size = result[1];
                break :blk .{ .unsubscribe = result[0] };
            },
            .unsuback => blk: {
                size = 2;
                const pid = try Pid.try_from(read_u16(data));
                break :blk .{ .unsuback = pid };
            },
        };
        if (size != header.remaining_len) {
            return error.InvalidRemainingLength;
        }
        return .{ packet, size };
    }

    pub fn encode(self: *const Packet, remaining_len: usize, data: []u8, idx: *usize) void {
        const VOID_PACKET_REMAINING_LEN: u8 = 0;
        switch (self.*) {
            .pingreq => {
                const CONTROL_BYTE: u8 = 0b11000000;
                write_bytes_idx(data, &.{ CONTROL_BYTE, VOID_PACKET_REMAINING_LEN }, idx);
            },
            .pingresp => {
                const CONTROL_BYTE: u8 = 0b11010000;
                write_bytes_idx(data, &.{ CONTROL_BYTE, VOID_PACKET_REMAINING_LEN }, idx);
            },
            .connect => |inner| {
                const CONTROL_BYTE: u8 = 0b00010000;
                encode_packet(Connect, inner, CONTROL_BYTE, remaining_len, data, idx);
            },
            .connack => |inner| {
                const CONTROL_BYTE: u8 = 0b00100000;
                const REMAINING_LEN: u8 = 2;
                const flags: u8 = if (inner.session_present) 1 else 0;
                const rc: u8 = @intFromEnum(inner.code);
                write_bytes_idx(data, &.{ CONTROL_BYTE, REMAINING_LEN, flags, rc }, idx);
            },
            .publish => |inner| {
                var control_byte: u8 = switch (inner.qos_pid) {
                    .level0 => 0b00110000,
                    .level1 => |_| 0b00110010,
                    .level2 => |_| 0b00110100,
                };
                if (inner.dup) {
                    control_byte |= 0b00001000;
                }
                if (inner.retain) {
                    control_byte |= 0b00000001;
                }
                encode_packet(Publish, inner, control_byte, remaining_len, data, idx);
            },
            .puback => |pid| {
                const CONTROL_BYTE: u8 = 0b01000000;
                encode_with_pid(CONTROL_BYTE, pid, data, idx);
            },
            .pubrec => |pid| {
                const CONTROL_BYTE: u8 = 0b01010000;
                encode_with_pid(CONTROL_BYTE, pid, data, idx);
            },
            .pubrel => |pid| {
                const CONTROL_BYTE: u8 = 0b01100010;
                encode_with_pid(CONTROL_BYTE, pid, data, idx);
            },
            .pubcomp => |pid| {
                const CONTROL_BYTE: u8 = 0b01110000;
                encode_with_pid(CONTROL_BYTE, pid, data, idx);
            },
            .subscribe => |inner| {
                const CONTROL_BYTE: u8 = 0b10000010;
                encode_packet(Subscribe, inner, CONTROL_BYTE, remaining_len, data, idx);
            },
            .suback => |inner| {
                const CONTROL_BYTE: u8 = 0b10010000;
                encode_packet(Suback, inner, CONTROL_BYTE, remaining_len, data, idx);
            },
            .unsubscribe => |inner| {
                const CONTROL_BYTE: u8 = 0b10100010;
                encode_packet(Unsubscribe, inner, CONTROL_BYTE, remaining_len, data, idx);
            },
            .unsuback => |pid| {
                const CONTROL_BYTE: u8 = 0b10110000;
                encode_with_pid(CONTROL_BYTE, pid, data, idx);
            },
            .disconnect => {
                const CONTROL_BYTE: u8 = 0b11100000;
                write_bytes_idx(data, &.{ CONTROL_BYTE, VOID_PACKET_REMAINING_LEN }, idx);
            },
        }
    }

    pub const EncodeLen = struct {
        total_len: usize,
        remaining_len: usize,
    };

    pub fn encode_len(self: *const Packet) MqttError!EncodeLen {
        const remaining_len = switch (self.*) {
            .pingreq => 2,
            .pingresp => 2,
            .disconnect => 2,
            .connack => |_| 4,
            .puback => |_| 4,
            .pubrec => |_| 4,
            .pubrel => |_| 4,
            .pubcomp => |_| 4,
            .unsuback => |_| 4,
            .connect => |inner| inner.encode_len(),
            .publish => |inner| inner.encode_len(),
            .subscribe => |inner| inner.encode_len(),
            .suback => |inner| inner.encode_len(),
            .unsubscribe => |inner| inner.encode_len(),
        };
        const total_len = try utils.total_length(remaining_len);
        return .{ .total_len = total_len, .remaining_len = remaining_len };
    }
};

pub const Header = struct {
    typ: PacketType,
    dup: bool,
    qos: QoS,
    retain: bool,
    remaining_len: u32,

    /// Decode packet header.
    ///
    /// Return null mean EOF reached.
    pub fn decode(data: []const u8) MqttError!?struct { Header, usize } {
        if (data.len < 2) {
            return null;
        }
        if (try utils.decode_var_int(data[1..])) |result| {
            const header = try Header.new_with(data[0], result[0]);
            return .{ header, result[1] + 1 };
        } else {
            return null;
        }
    }

    pub fn new_with(hd: u8, remaining_len: u32) MqttError!Header {
        const FLAGS_MASK: u8 = 0b1111;
        const result: struct { PacketType, bool } = switch (hd >> 4) {
            1 => .{ .connect, hd & FLAGS_MASK == 0 },
            2 => .{ .connack, hd & FLAGS_MASK == 0 },
            3 => {
                return .{
                    .typ = .publish,
                    .dup = hd & 0b1000 != 0,
                    .qos = try QoS.from_u8((hd & 0b110) >> 1),
                    .retain = hd & 1 == 1,
                    .remaining_len = remaining_len,
                };
            },
            4 => .{ .puback, hd & FLAGS_MASK == 0 },
            5 => .{ .pubrec, hd & FLAGS_MASK == 0 },
            6 => .{ .pubrel, hd & FLAGS_MASK == 0b0010 },
            7 => .{ .pubcomp, hd & FLAGS_MASK == 0 },
            8 => .{ .subscribe, hd & FLAGS_MASK == 0b0010 },
            9 => .{ .suback, hd & FLAGS_MASK == 0 },
            10 => .{ .unsubscribe, hd & FLAGS_MASK == 0b0010 },
            11 => .{ .unsuback, hd & FLAGS_MASK == 0 },
            12 => .{ .pingreq, hd & FLAGS_MASK == 0 },
            13 => .{ .pingresp, hd & FLAGS_MASK == 0 },
            14 => .{ .disconnect, hd & FLAGS_MASK == 0 },
            else => return error.InvalidHeader,
        };
        if (!result[1]) {
            return error.InvalidHeader;
        }
        return .{
            .typ = result[0],
            .dup = false,
            .qos = .level0,
            .retain = false,
            .remaining_len = remaining_len,
        };
    }
};

fn encode_with_pid(control_byte: u8, pid: Pid, data: []u8, idx: *usize) void {
    const REMAINING_LEN: u8 = 2;
    const high: u8 = @intCast(pid.value >> 8);
    const low: u8 = @intCast(pid.value & 0xFF);
    write_bytes_idx(data, &.{ control_byte, REMAINING_LEN, high, low }, idx);
}

test "test all decls" {
    testing.refAllDecls(Packet);
    testing.refAllDecls(Header);
    testing.refAllDecls(Connect);
    testing.refAllDecls(Connack);
    testing.refAllDecls(Publish);
    testing.refAllDecls(Subscribe);
    testing.refAllDecls(Suback);
    testing.refAllDecls(Unsubscribe);
}
