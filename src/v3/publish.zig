const types = @import("../types.zig");
const QosPid = types.QosPid;
const TopicName = types.TopicName;

/// Publish packet body type.
pub const Publish = struct {
    dup: bool,
    retain: bool,
    qos_pid: QosPid,
    topic_name: TopicName,
    payload: []const u8,
};
