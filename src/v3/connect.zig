const std = @import("std");

const utils = @import("../utils.zig");
const types = @import("../types.zig");
const MqttError = @import("../error.zig").MqttError;
const packet = @import("packet.zig");

const Allocator = std.mem.Allocator;
const Utf8View = std.unicode.Utf8View;
const read_u8_idx = utils.read_u8_idx;
const read_u16_idx = utils.read_u16_idx;
const read_bytes_idx = utils.read_bytes_idx;
const read_string_idx = utils.read_string_idx;
const write_u8_idx = utils.write_u8_idx;
const write_u16_idx = utils.write_u16_idx;
const write_bytes_idx = utils.write_bytes_idx;
const Header = packet.Header;
const QoS = types.QoS;
const Protocol = types.Protocol;
const TopicName = types.TopicName;
const Allocated = types.Allocated;

/// Connect packet body type.
pub const Connect = struct {
    protocol: Protocol,
    clean_session: bool,
    keep_alive: u16,
    client_id: Utf8View,
    last_will: ?LastWill = null,
    username: ?Utf8View = null,
    password: ?[]const u8 = null,

    // To store data in Connect packet.
    allocated: ?Allocated = null,

    pub fn decode(
        data: []const u8,
        header: Header,
        allocator: Allocator,
    ) MqttError!struct { Connect, usize } {
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
        var idx: usize = 0;
        const content = try allocator.alloc(u8, header.remaining_len - idx_0);
        @memcpy(content, data[idx_0..header.remaining_len]);
        const allocated = .{ .content = content, .allocator = allocator };

        const client_id = try read_string_idx(content[idx..], &idx);
        var last_will: ?LastWill = null;
        var username: ?Utf8View = null;
        var password: ?[]const u8 = null;
        if (connect_flags & 0b100 != 0) {
            const topic_name = try read_string_idx(content[idx..], &idx);
            const message = try read_bytes_idx(content[idx..], &idx);
            last_will = .{
                .topic_name = try TopicName.try_from(topic_name),
                .message = message,
                .qos = try QoS.from_u8((connect_flags & 0b11000) >> 3),
                .retain = (connect_flags & 0b00100000) != 0,
                .allocated = allocated,
            };
        } else if (connect_flags & 0b11000 != 0) {
            return error.InvalidConnectFlags;
        }
        if (connect_flags & 0b10000000 != 0) {
            username = try read_string_idx(content[idx..], &idx);
        }
        if (connect_flags & 0b01000000 != 0) {
            password = try read_bytes_idx(content[idx..], &idx);
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
            .allocated = allocated,
        };
        return .{ value, idx_0 + idx };
    }

    pub fn encode(self: *const Connect, data: []u8, idx: *usize) void {
        var connect_flags: u8 = 0b00000000;
        if (self.clean_session) {
            connect_flags |= 0b10;
        }
        if (self.username) |_| {
            connect_flags |= 0b10000000;
        }
        if (self.password) |_| {
            connect_flags |= 0b01000000;
        }
        if (self.last_will) |last_will| {
            connect_flags |= 0b00000100;
            connect_flags |= @intFromEnum(last_will.qos) << 3;
            if (last_will.retain) {
                connect_flags |= 0b00100000;
            }
        }

        self.protocol.encode(data, idx);
        write_u8_idx(data, connect_flags, idx);
        write_u16_idx(data, self.keep_alive, idx);
        write_bytes_idx(data, self.client_id.bytes, idx);
        if (self.last_will) |last_will| {
            last_will.encode(data, idx);
        }
        if (self.username) |username| {
            write_bytes_idx(data, username.bytes, idx);
        }
        if (self.password) |password| {
            write_bytes_idx(data, password, idx);
        }
    }

    pub fn encode_len(self: *const Connect) usize {
        var length = self.protocol.encode_len();
        // flags + keep-alive
        length += 1 + 2;
        // client identifier
        length += 2 + self.client_id.bytes.len;
        if (self.last_will) |last_will| {
            length += last_will.encode_len();
        }
        if (self.username) |username| {
            length += 2 + username.bytes.len;
        }
        if (self.password) |password| {
            length += 2 + password.len;
        }
        return length;
    }

    pub fn deinit(self: Connect) void {
        if (self.allocated) |allocated| {
            allocated.deinit();
        }
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
    allocated: ?Allocated = null,

    pub fn encode(self: *const LastWill, data: []u8, idx: *usize) void {
        write_bytes_idx(data, self.topic_name.value.bytes, idx);
        write_bytes_idx(data, self.message, idx);
    }

    pub fn encode_len(self: *const LastWill) usize {
        return 4 + self.topic_name.len() + self.message.len;
    }

    pub fn deinit(self: *LastWill) void {
        if (self.allocated) |allocated| {
            allocated.deinit();
        }
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
