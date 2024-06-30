const types = @import("../types.zig");
const MqttError = @import("../error.zig").MqttError;
const packet = @import("./packet.zig");

const QosPid = types.QosPid;
const TopicName = types.TopicName;
const Header = packet.Header;

/// Publish packet body type.
pub const Publish = struct {
    dup: bool,
    retain: bool,
    qos_pid: QosPid,
    topic_name: TopicName,
    payload: []const u8,

    pub fn decode(_: []const u8, _: Header) MqttError!struct { Publish, usize } {
        return error.InvalidRemainingLength;
    }

    pub fn encode(_: *const Publish, _: []u8, _: *usize) void {}

    pub fn encode_len(_: *const Publish) usize {
        return 0;
    }
};
