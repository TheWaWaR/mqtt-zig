const types = @import("../types.zig");
const MqttError = @import("../error.zig").MqttError;
const QoS = types.QoS;
const Protocol = types.Protocol;
const TopicName = types.TopicName;

/// Connect packet body type.
pub const Connect = struct {
    protocol: Protocol,
    clean_session: bool,
    keep_alive: u16,
    client_id: []const u8,
    last_will: ?LastWill,
    username: ?[]const u8,
    password: ?[]const u8,

    pub fn decode(_: []const u8) MqttError!struct { Connect, usize } {
        return error.InvalidRemainingLength;
    }
};

/// Connack packet body type.
pub const Connack = struct {
    session_present: bool,
    code: ConnectReturnCode,

    pub fn decode(_: []const u8) MqttError!struct { Connack, usize } {
        return error.InvalidRemainingLength;
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
};
