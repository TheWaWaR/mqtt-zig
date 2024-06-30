const std = @import("std");

const utils = @import("../utils.zig");
const types = @import("../types.zig");
const MqttError = @import("../error.zig").MqttError;
const packet = @import("packet.zig");

const mem = std.mem;
const Allocator = mem.Allocator;
const Utf8View = std.unicode.Utf8View;
const read_u8_idx = utils.read_u8_idx;
const read_u16_idx = utils.read_u16_idx;
const read_bytes_idx = utils.read_bytes_idx;
const read_string_idx = utils.read_string_idx;
const Header = packet.Header;
const QoS = types.QoS;
const Protocol = types.Protocol;
const TopicName = types.TopicName;

/// Connect packet body type.
pub const Connect = struct {
    protocol: Protocol,
    clean_session: bool,
    keep_alive: u16,
    client_id: Utf8View,
    last_will: ?LastWill,
    username: ?Utf8View,
    password: ?[]const u8,

    // To store data in Connect packet.
    content: []u8,
    allocator: Allocator,

    pub fn decode(data: []const u8, header: Header, allocator: Allocator) MqttError!struct { Connect, usize } {
        const result = (try Protocol.decode(data)) orelse return error.InvalidRemainingLength;
        const protocol = result[0];
        if (@intFromEnum(protocol) > 4) {
            return error.UnexpectedProtocol;
        }
        var idx_0: usize = result[1];
        const connect_flags = read_u8_idx(data[idx_0..], &idx_0);
        if (connect_flags & 1 != 0) {
            return error.InvalidConnectFlags;
        }
        const keep_alive = read_u16_idx(data[idx_0..], &idx_0);

        // allocate new memory
        const content = try allocator.alloc(u8, header.remaining_len - idx_0);
        mem.copyForwards(u8, content, data[idx_0..header.remaining_len]);
        var idx: usize = 0;

        const client_id = try read_string_idx(content[idx..], &idx);
        var last_will: ?LastWill = null;
        var username: ?Utf8View = null;
        var password: ?[]const u8 = null;
        if (connect_flags & 0b100 != 0) {
            const topic_name = try read_string_idx(content[idx..], &idx);
            const message = read_bytes_idx(content[idx..], &idx);
            last_will = .{
                .topic_name = try TopicName.try_from(topic_name),
                .message = message,
                .qos = try QoS.from_u8((connect_flags & 0b11000) >> 3),
                .retain = (connect_flags & 0b00100000) != 0,
                .content = content,
                .allocator = allocator,
            };
        } else if (connect_flags & 0b11000 != 0) {
            return error.InvalidConnectFlags;
        }
        if (connect_flags & 0b10000000 != 0) {
            username = try read_string_idx(content[idx..], &idx);
        }
        if (connect_flags & 0b01000000 != 0) {
            password = read_bytes_idx(content[idx..], &idx);
        }
        const clean_session = (connect_flags & 0b10) != 0;
        const value = .{
            .protocol = protocol,
            .keep_alive = keep_alive,
            .client_id = client_id,
            .username = username,
            .password = password,
            .last_will = last_will,
            .clean_session = clean_session,

            .content = content,
            .allocator = allocator,
        };
        return .{ value, idx_0 + idx };
    }

    pub fn deinit(self: *Connect) void {
        self.allocator.free(self.content);
    }
};

/// Connack packet body type.
pub const Connack = struct {
    session_present: bool,
    code: ConnectReturnCode,

    pub fn decode(data: []const u8) MqttError!struct { Connack, usize } {
        const session_present = switch (data[0]) {
            0 => false,
            1 => true,
            else => return error.InvalidConnackFlags,
        };
        const code = try ConnectReturnCode.from_u8(data[1]);
        const value = .{ .session_present = session_present, .code = code };
        return .{ value, 2 };
    }
};

/// Message that the server should publish when the client disconnects.
///
/// Sent by the client in the [Connect] packet. [MQTT 3.1.3.3].
///
/// [MQTT 3.1.3.3]: http://docs.oasis-open.org/mqtt/mqtt/v3.1.1/os/mqtt-v3.1.1-os.html#_Toc398718031
pub const LastWill = struct {
    qos: QoS,
    retain: bool,
    topic_name: TopicName,
    message: []const u8,

    // NOTE: be careful free twice!
    content: []u8,
    allocator: Allocator,

    pub fn deinit(self: *Connect) void {
        self.allocator.free(self.content);
    }
};

/// Return code of a [Connack] packet.
///
/// See [MQTT 3.2.2.3] for interpretations.
///
/// [MQTT 3.2.2.3]: http://docs.oasis-open.org/mqtt/mqtt/v3.1.1/os/mqtt-v3.1.1-os.html#_Toc398718035
pub const ConnectReturnCode = enum(u8) {
    accepted = 0,
    unacceptable_protocol_version = 1,
    identifier_rejected = 2,
    server_unavailable = 3,
    bad_username_or_password = 4,
    not_authorized = 5,

    pub fn from_u8(byte: u8) MqttError!ConnectReturnCode {
        return switch (byte) {
            0 => .accepted,
            1 => .unacceptable_protocol_version,
            2 => .identifier_rejected,
            3 => .server_unavailable,
            4 => .bad_username_or_password,
            5 => .not_authorized,
            else => error.InvalidConnectReturnCode,
        };
    }
};
