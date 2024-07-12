const std = @import("std");

const types = @import("../types.zig");
const utils = @import("../utils.zig");
const MqttError = @import("../error.zig").MqttError;
const connect = @import("./connect.zig");
const publish = @import("./publish.zig");
const subscribe = @import("./subscribe.zig");

const testing = std.testing;
const Utf8View = std.unicode.Utf8View;

const read_u16 = utils.read_u16;
const write_bytes = utils.write_bytes;
const encode_packet = utils.encode_packet;
const Pid = types.Pid;
const QoS = types.QoS;

pub const Connect = connect.Connect;
pub const Connack = connect.Connack;
pub const LastWill = connect.LastWill;
pub const ConnectReturnCode = connect.ConnectReturnCode;
pub const Publish = publish.Publish;
pub const Subscribe = subscribe.Subscribe;
pub const FilterWithQoSListView = subscribe.FilterWithQoSListView;
pub const FilterWithQoS = subscribe.FilterWithQoS;
pub const Suback = subscribe.Suback;
pub const ReturnCodeListView = subscribe.ReturnCodeListView;
pub const Unsubscribe = subscribe.Unsubscribe;
pub const FilterListView = subscribe.FilterListView;
pub const SubscribeReturnCode = subscribe.SubscribeReturnCode;

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
    /// it will return `error.ReadBufNotEnough`. The decoded packet's fields
    /// will reference the source `data`.
    pub fn decode(data: []const u8) MqttError!Packet {
        const header, const header_len = try Header.decode(data);
        return Packet.decode_with(data[header_len..], header, null);
    }

    /// Decode a packet from some bytes. If not enough bytes to decode a packet,
    /// it will return `error.ReadBufNotEnough`. The decoded packet's fields
    /// will copy into `keep_data` and reference to it if given, otherwise the
    /// fields will reference to `data`.
    pub fn decode_with(data: []const u8, header: Header, keep_data: ?[]u8) MqttError!Packet {
        if (data.len < header.remaining_len) {
            return error.ReadBufNotEnough;
        }
        var size: usize = 0;
        const packet: Packet = switch (header.typ) {
            .pingreq => .pingreq,
            .pingresp => .pingresp,
            .disconnect => .disconnect,
            .connect => blk: {
                const result = try Connect.decode(data, header, keep_data);
                size = result[1];
                break :blk .{ .connect = result[0] };
            },
            .connack => blk: {
                const result = try Connack.decode(data);
                size = result[1];
                break :blk .{ .connack = result[0] };
            },
            .publish => blk: {
                const result = try Publish.decode(data, header, keep_data);
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
                const result = try Subscribe.decode(data, header, keep_data);
                size = result[1];
                break :blk .{ .subscribe = result[0] };
            },
            .suback => blk: {
                const result = try Suback.decode(data, header, keep_data);
                size = result[1];
                break :blk .{ .suback = result[0] };
            },
            .unsubscribe => blk: {
                const result = try Unsubscribe.decode(data, header, keep_data);
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
        return packet;
    }

    pub fn encode(self: *const Packet, data: []u8, idx: *usize) MqttError!void {
        const info = try self.encode_len();
        return self.encode_with(info, data, idx);
    }

    pub fn encode_with(self: *const Packet, info: EncodeLen, data: []u8, idx: *usize) MqttError!void {
        if (info.total_len > data.len) {
            return error.WriteBufNotEnough;
        }
        const remaining_len = info.remaining_len;
        const VOID_PACKET_REMAINING_LEN: u8 = 0;
        switch (self.*) {
            .pingreq => {
                const CONTROL_BYTE: u8 = 0b11000000;
                write_bytes(data, idx, &.{ CONTROL_BYTE, VOID_PACKET_REMAINING_LEN });
            },
            .pingresp => {
                const CONTROL_BYTE: u8 = 0b11010000;
                write_bytes(data, idx, &.{ CONTROL_BYTE, VOID_PACKET_REMAINING_LEN });
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
                write_bytes(data, idx, &.{ CONTROL_BYTE, REMAINING_LEN, flags, rc });
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
                write_bytes(data, idx, &.{ CONTROL_BYTE, VOID_PACKET_REMAINING_LEN });
            },
        }
    }

    pub const EncodeLen = struct {
        total_len: usize,
        remaining_len: usize,
    };

    pub fn encode_len(self: *const Packet) MqttError!EncodeLen {
        const remaining_len = switch (self.*) {
            .pingreq => 0,
            .pingresp => 0,
            .disconnect => 0,
            .connack => |_| 2,
            .puback => |_| 2,
            .pubrec => |_| 2,
            .pubrel => |_| 2,
            .pubcomp => |_| 2,
            .unsuback => |_| 2,
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
    /// Return `error.ReadBufNotEnough` mean EOF reached.
    pub fn decode(data: []const u8) MqttError!struct { Header, usize } {
        if (data.len < 2) {
            return error.ReadBufNotEnough;
        }
        if (try utils.decode_var_int(data[1..])) |result| {
            const header = try Header.new_with(data[0], result[0]);
            return .{ header, result[1] + 1 };
        } else {
            return error.ReadBufNotEnough;
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
    write_bytes(data, idx, &.{ control_byte, REMAINING_LEN, high, low });
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

fn assert_encode(pkt: Packet, total_len: usize) !void {
    // Test Packet.encode_with()
    const info = try pkt.encode_len();
    try testing.expectEqual(info.total_len, total_len);
    var write_buf: [1024]u8 = undefined;
    var write_idx: usize = 0;
    try pkt.encode_with(info, write_buf[0..], &write_idx);
    try testing.expectEqual(write_idx, total_len);

    // Test Packet.encode()
    var write_buf1: [1024]u8 = undefined;
    var write_idx1: usize = 0;
    try pkt.encode(write_buf1[0..], &write_idx1);
    try testing.expect(utils.eql(write_buf[0..write_idx], write_buf1[0..write_idx1]));

    // Test Packet.decode()
    const read0_pkt = try Packet.decode(write_buf[0..]);
    try testing.expect(utils.eql(pkt, read0_pkt));

    // Test Packet.decode_with()
    const header, const header_len = (try Header.decode(write_buf[0..]));
    try testing.expectEqual(header_len + header.remaining_len, total_len);
    const read1_pkt = (try Packet.decode_with(write_buf[header_len..], header, null));
    try testing.expect(utils.eql(pkt, read1_pkt));
    var out_buf: [1024]u8 = undefined;
    const read2_pkt = (try Packet.decode_with(write_buf[header_len..], header, out_buf[0..]));
    try testing.expect(utils.eql(pkt, read2_pkt));
}

test "packet: CONNECT" {
    try assert_encode(Packet{ .connect = Connect{
        .protocol = .V311,
        .clean_session = true,
        .keep_alive = 120,
        .client_id = Utf8View.initUnchecked("sample"),
    } }, 20);

    try assert_encode(Packet{ .connect = Connect{
        .protocol = .V311,
        .clean_session = true,
        .keep_alive = 120,
        .client_id = Utf8View.initUnchecked("sample"),
        .last_will = LastWill{
            .qos = .level1,
            .retain = true,
            .topic_name = try types.TopicName.try_from(Utf8View.initUnchecked("abc")),
            .message = "msg-content",
        },
        .username = Utf8View.initUnchecked("username"),
        .password = "password",
    } }, 58);

    try assert_encode(Packet{ .connect = Connect{
        .protocol = .V310,
        .keep_alive = 120,
        .client_id = Utf8View.initUnchecked("sample"),
        .clean_session = true,
    } }, 22);
}

test "packet: CONNACK" {
    try assert_encode(Packet{ .connack = Connack{
        .session_present = true,
        .code = .accepted,
    } }, 4);
}

test "packet: PUBLISH, PUBACK, PUBREC, PUBREL, PUBCOMP" {
    try assert_encode(Packet{ .publish = Publish{
        .dup = false,
        .qos_pid = types.QosPid{ .level2 = try Pid.try_from(10) },
        .retain = true,
        .topic_name = try types.TopicName.try_from(Utf8View.initUnchecked("asdf")),
        .payload = "hello",
    } }, 15);

    try assert_encode(Packet{ .puback = try Pid.try_from(19) }, 4);
    try assert_encode(Packet{ .pubrec = try Pid.try_from(19) }, 4);
    try assert_encode(Packet{ .pubrel = try Pid.try_from(19) }, 4);
    try assert_encode(Packet{ .pubcomp = try Pid.try_from(19) }, 4);
}

test "packet: SUBSCRIBE, SUBACK" {
    var topics1_buf: [128]u8 = undefined;
    const items1: []const FilterWithQoS = &.{
        .{ .filter = try types.TopicFilter.try_from(Utf8View.initUnchecked("a/b")), .qos = .level2 },
        .{ .filter = try types.TopicFilter.try_from(Utf8View.initUnchecked("+")), .qos = .level1 },
    };
    const topics1 = FilterWithQoSListView.encode_to_view(items1, topics1_buf[0..]);
    var topics1_iter = topics1.iterator();
    var i_1: usize = 0;
    while (topics1_iter.next()) |topic| {
        try testing.expect(utils.eql(topic, items1[i_1]));
        i_1 += 1;
    }
    try testing.expectEqual(i_1, 2);
    const pkt1 = Packet{ .subscribe = Subscribe{
        .pid = try Pid.try_from(345),
        .topics = topics1,
    } };
    try assert_encode(pkt1, 14);

    var topics2_buf: [128]u8 = undefined;
    const items2: []const SubscribeReturnCode = &.{.max_level2};
    const topics2 = ReturnCodeListView.encode_to_view(items2, topics2_buf[0..]);
    var topics2_iter = topics2.iterator();
    var i_2: usize = 0;
    while (topics2_iter.next()) |topic| {
        try testing.expect(utils.eql(topic, items2[i_2]));
        i_2 += 1;
    }
    try testing.expectEqual(i_2, 1);
    const pkt2 = Packet{ .suback = Suback{
        .pid = try Pid.try_from(12321),
        .topics = topics2,
    } };
    try assert_encode(pkt2, 5);
}

test "packet: UNSUBSCRIBE, UNSUBACK" {
    var topics_buf: [128]u8 = undefined;
    const topics = FilterListView.encode_to_view(
        &.{try types.TopicFilter.try_from(Utf8View.initUnchecked("a/b"))},
        topics_buf[0..],
    );
    const pkt = Packet{ .unsubscribe = Unsubscribe{
        .pid = try Pid.try_from(12321),
        .topics = topics,
    } };
    try assert_encode(pkt, 9);

    try assert_encode(Packet{ .unsuback = try Pid.try_from(19) }, 4);
}

test "packet: PINGREQ, PINGRESP, DISCONNECT" {
    try assert_encode(Packet.pingreq, 2);
    try assert_encode(Packet.pingresp, 2);
    try assert_encode(Packet.disconnect, 2);
}
