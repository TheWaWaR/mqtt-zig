const std = @import("std");
const types = @import("../types.zig");
const MqttError = @import("../error.zig").MqttError;
const packet = @import("./packet.zig");

const ArrayList = std.ArrayList;

const Header = packet.Header;
const QoS = types.QoS;
const Pid = types.Pid;
const QosPid = types.QosPid;
const Protocol = types.Protocol;
const TopicName = types.TopicName;
const TopicFilter = types.TopicFilter;

/// Subscribe packet body type.
pub const Subscribe = struct {
    pid: Pid,
    topics: ArrayList(FilterWithQoS),

    pub fn decode(_: []const u8, _: Header) MqttError!struct { Subscribe, usize } {
        return error.InvalidRemainingLength;
    }
};

pub const FilterWithQoS = struct {
    filter: TopicFilter,
    qos: QoS,
};

/// Suback packet body type.
pub const Suback = struct {
    pid: Pid,
    topics: ArrayList(SubscribeReturnCode),

    pub fn decode(_: []const u8, _: Header) MqttError!struct { Suback, usize } {
        return error.InvalidRemainingLength;
    }
};

/// Unsubscribe packet body type.
pub const Unsubscribe = struct {
    pid: Pid,
    topics: ArrayList(TopicFilter),

    pub fn decode(_: []const u8, _: Header) MqttError!struct { Unsubscribe, usize } {
        return error.InvalidRemainingLength;
    }
};

/// Subscribe return code type.
pub const SubscribeReturnCode = enum(u8) {
    max_level0 = 0,
    max_level1 = 1,
    max_level2 = 2,
    failure = 0x80,
};
