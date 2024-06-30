const std = @import("std");

const types = @import("../types.zig");
const utils = @import("../utils.zig");
const MqttError = @import("../error.zig").MqttError;
const connect = @import("./connect.zig");
const publish = @import("./publish.zig");
const subscribe = @import("./subscribe.zig");

const testing = std.testing;

const read_u16_unchecked = utils.read_u16_unchecked;
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
    pingreq: void,
    /// [MQTT 3.13](http://docs.oasis-open.org/mqtt/mqtt/v3.1.1/os/mqtt-v3.1.1-os.html#_Toc398718086)
    pingresp: void,
    /// [MQTT 3.14](http://docs.oasis-open.org/mqtt/mqtt/v3.1.1/os/mqtt-v3.1.1-os.html#_Toc398718090)
    disconnect: void,

    /// Decode a packet from some bytes. If not enough bytes to decode a packet,
    /// it will return `null`.
    pub fn decode(data: []const u8, header: Header) MqttError!?struct { Packet, usize } {
        if (data.len < header.remaining_len) {
            return null;
        }
        var size: usize = 0;
        const packet: Packet = switch (header.typ) {
            .pingreq => .pingreq,
            .pingresp => .pingresp,
            .disconnect => .disconnect,
            .connect => blk: {
                const result = try Connect.decode(data);
                size = result[1];
                break :blk .{ .connect = result[0] };
            },
            .connack => blk: {
                const result = try Connack.decode(data);
                size = result[1];
                break :blk .{ .connack = result[0] };
            },
            .publish => blk: {
                const result = try Publish.decode(data, header);
                size = result[1];
                break :blk .{ .publish = result[0] };
            },
            .puback => blk: {
                size = 2;
                const pid = try Pid.try_from(read_u16_unchecked(data));
                break :blk .{ .puback = pid };
            },
            .pubrec => blk: {
                size = 2;
                const pid = try Pid.try_from(read_u16_unchecked(data));
                break :blk .{ .pubrec = pid };
            },
            .pubrel => blk: {
                size = 2;
                const pid = try Pid.try_from(read_u16_unchecked(data));
                break :blk .{ .pubrel = pid };
            },
            .pubcomp => blk: {
                size = 2;
                const pid = try Pid.try_from(read_u16_unchecked(data));
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
                const pid = try Pid.try_from(read_u16_unchecked(data));
                break :blk .{ .unsuback = pid };
            },
        };
        if (size != header.remaining_len) {
            return error.InvalidRemainingLength;
        }
        return .{ packet, size };
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

test "test all decls" {
    testing.refAllDecls(Packet);
    testing.refAllDecls(Header);
}
