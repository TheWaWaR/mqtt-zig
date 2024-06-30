const std = @import("std");

pub const MqttError = error{
    /// Invalid remaining length.
    InvalidRemainingLength,

    /// No subscription in subscribe packet.
    EmptySubscription,

    /// Packet identifier is 0.
    ZeroPid,

    /// Invalid QoS value.
    InvalidQos,

    /// Invalid connect flags.
    InvalidConnectFlags,

    /// Invalid connack flags (not 0 or 1).
    InvalidConnackFlags,

    /// Invalid connect return code (value > 5).
    InvalidConnectReturnCode,

    /// Invalid protocol.
    InvalidProtocol,

    /// Unexpected protocol
    UnexpectedProtocol,

    /// Invalid fixed header (packet type, flags, or remaining_length).
    InvalidHeader,

    /// Invalid variable byte integer, the value MUST smaller than `268,435,456`.
    InvalidVarByteInt,

    /// Invalid Topic Name
    InvalidTopicName,

    /// Invalid topic filter
    InvalidTopicFilter,

    /// Trying to decode a non-utf8 string.
    InvalidString,
} || std.mem.Allocator.Error;
