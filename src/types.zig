const std = @import("std");
const math = std.math;
const testing = std.testing;

const MqttError = @import("error.zig").MqttError;
const consts = @import("consts.zig");

/// Protocol version.
pub const Protocol = enum(u8) {
    /// [MQTT 3.1]
    ///
    /// [MQTT 3.1]: https://public.dhe.ibm.com/software/dw/webservices/ws-mqtt/mqtt-v3r1.html
    V310 = 3,

    /// [MQTT 3.1.1] is the most commonly implemented version.
    ///
    /// [MQTT 3.1.1]: https://docs.oasis-open.org/mqtt/mqtt/v3.1.1/os/mqtt-v3.1.1-os.html
    V311 = 4,

    /// [MQTT 5.0] is the latest version
    ///
    /// [MQTT 5.0]: https://docs.oasis-open.org/mqtt/mqtt/v5.0/os/mqtt-v5.0-os.html
    V500 = 5,

    pub fn try_from(name: []const u8, level: u8) MqttError!Protocol {
        if (std.meta.eql(name, consts.MQTT)) {
            switch (level) {
                4 => return .V311,
                5 => return .V500,
                else => {},
            }
        }
        if (std.meta.eql(name, consts.MQISDP) and level == 3) {
            return .V310;
        }
        return error.InvalidProtocol;
    }
};

test "parse protocol" {
    try testing.expect((try Protocol.try_from("MQIsdp", 3)) == .V310);
    try testing.expect((try Protocol.try_from("MQTT", 4)) == .V311);
    try testing.expect((try Protocol.try_from("MQTT", 5)) == .V500);

    try testing.expect(Protocol.try_from("MQIsdp", 4) == error.InvalidProtocol);
    try testing.expect(Protocol.try_from("MQISDP", 3) == error.InvalidProtocol);
    try testing.expect(Protocol.try_from("MQTT", 3) == error.InvalidProtocol);
    try testing.expect(Protocol.try_from("mqtt", 4) == error.InvalidProtocol);
}

/// Packet identifier
pub const Pid = struct {
    value: u16 = 1,

    pub fn try_from(value: u16) MqttError!Pid {
        if (value == 0) {
            return error.ZeroPid;
        } else {
            return .{ .value = value };
        }
    }

    /// Adding a `u16` to a `Pid` will wrap around and avoid 0.
    pub fn add(self: Pid, n: u16) Pid {
        const ov = @addWithOverflow(self.value, n);
        if (ov[1] != 0) {
            return .{ .value = 1 };
        } else {
            return .{ .value = ov[0] };
        }
    }
};

/// Packet delivery [Quality of Service] level.
///
/// [Quality of Service]: http://docs.oasis-open.org/mqtt/mqtt/v3.1.1/os/mqtt-v3.1.1-os.html#_Toc398718099
pub const QoS = enum(u8) {
    /// `QoS 0`. At most once. No ack needed.
    Level0 = 0,
    /// `QoS 1`. At least once. One ack needed.
    Level1 = 1,
    /// `QoS 2`. Exactly once. Two acks needed.
    Level2 = 2,
};

/// Combined [`QoS`] and [`Pid`].
///
/// Used only in [`Publish`] packets.
pub const QosPid = union(QoS) {
    Level0: void,
    Level1: Pid,
    Level2: Pid,

    pub fn pid(self: QosPid) ?Pid {
        return switch (self) {
            QosPid.Level0 => null,
            QosPid.Level1 => |v| v,
            QosPid.Level2 => |v| v,
        };
    }

    pub fn qos(self: QosPid) QoS {
        return @as(QoS, self);
    }
};

/// Topic name.
///
/// See [MQTT 4.7].
///
/// [MQTT 4.http]: 7://docs.oasis-open.org/mqtt/mqtt/v3.1.1/os/mqtt-v3.1.1-os.html#_Toc398718106
pub const TopicName = struct {
    value: []const u8,

    pub fn try_from(value: []const u8) MqttError!TopicName {
        if (TopicName.is_invalid(value)) {
            return error.InvalidTopicName;
        }
        return .{ .value = value };
    }

    /// Check if the topic name is invalid.
    pub fn is_invalid(value: []const u8) bool {
        if (value.len > @as(usize, math.maxInt(u16))) {
            return true;
        }

        var utf8 = std.unicode.Utf8View.initUnchecked(value).iterator();
        while (utf8.nextCodepoint()) |c| {
            switch (c) {
                consts.MATCH_ONE_CHAR, consts.MATCH_ALL_CHAR, 0 => return true,
                else => {},
            }
        }
        return false;
    }

    pub fn is_shared(self: TopicName) bool {
        return std.mem.startsWith(u8, self.value, consts.SHARED_PREFIX);
    }
    pub fn is_sys(self: TopicName) bool {
        return std.mem.startsWith(u8, self.value, consts.SYS_PREFIX);
    }
};

test "validate topic name" {
    // valid topic name
    try testing.expect(!TopicName.is_invalid("/abc/def"));
    try testing.expect(!TopicName.is_invalid("abc/def"));
    try testing.expect(!TopicName.is_invalid("abc"));
    try testing.expect(!TopicName.is_invalid("/"));
    try testing.expect(!TopicName.is_invalid("//"));
    // NOTE: Because v5.0 topic alias, we let up level to check empty topic name
    try testing.expect(!TopicName.is_invalid(""));
    try testing.expect(!TopicName.is_invalid("a" ** 65535));

    // invalid topic name
    try testing.expect(TopicName.is_invalid("#"));
    try testing.expect(TopicName.is_invalid("+"));
    try testing.expect(TopicName.is_invalid("/+"));
    try testing.expect(TopicName.is_invalid("/#"));
    try testing.expect(TopicName.is_invalid("abc/\x00"));
    try testing.expect(TopicName.is_invalid("abc\x00def"));
    try testing.expect(TopicName.is_invalid("abc#def"));
    try testing.expect(TopicName.is_invalid("abc+def"));
    try testing.expect(TopicName.is_invalid("a" ** 65536));
}

pub const TopicFilter = struct {
    value: []const u8,
    shared_filter_sep: u16,

    /// Check if the topic filter is invalid.
    ///
    ///   * The u16 returned is where the bytes index of '/' char before shared
    ///   topic filter. If null returned, the topic filter is invalid.
    pub fn is_invalid(value: []const u8) ?u16 {
        if (value.len > @as(usize, math.maxInt(u16))) {
            return null;
        }
        // v5.0 [MQTT-4.7.3-1]
        if (value.len == 0) {
            return null;
        }

        var last_sep = @as(usize, math.maxInt(u16)) + 1;
        var has_all = false;
        var has_one = false;
        var char_idx: usize = 0;
        var byte_idx: usize = 0;
        var is_shared = true;
        var shared_group_sep: u16 = 0;
        var shared_filter_sep: u16 = 0;
        var utf8 = std.unicode.Utf8View.initUnchecked(value).iterator();
        while (utf8.nextCodepoint()) |c| {
            if (c == 0) {
                return null;
            }
            // "#" must be last char
            if (has_all) {
                return null;
            }

            if (is_shared and char_idx < 7 and c != consts.SHARED_PREFIX[char_idx]) {
                is_shared = false;
            }

            if (c == consts.LEVEL_SEP) {
                if (is_shared) {
                    if (shared_group_sep == 0) {
                        shared_group_sep = @as(u16, @intCast(byte_idx));
                    } else if (shared_filter_sep == 0) {
                        shared_filter_sep = @as(u16, @intCast(byte_idx));
                    }
                }
                // "+" must occupy an entire level of the filter
                if (has_one and char_idx != last_sep + 2 and char_idx != 1) {
                    return null;
                }
                last_sep = char_idx;
                has_one = false;
            } else if (c == consts.MATCH_ALL_CHAR) {
                // v5.0 [MQTT-4.8.2-2]
                if (shared_group_sep > 0 and shared_filter_sep == 0) {
                    return null;
                }
                if (has_one) {
                    // invalid topic filter: "/+#"
                    return null;
                } else if (char_idx == last_sep + 1 or char_idx == 0) {
                    has_all = true;
                } else {
                    // invalid topic filter: "/ab#"
                    return null;
                }
            } else if (c == consts.MATCH_ONE_CHAR) {
                // v5.0 [MQTT-4.8.2-2]
                if (shared_group_sep > 0 and shared_filter_sep == 0) {
                    return null;
                }
                if (has_one) {
                    // invalid topic filter: "/++"
                    return null;
                } else if (char_idx == last_sep + 1 or char_idx == 0) {
                    has_one = true;
                } else {
                    return null;
                }
            }

            char_idx += 1;
            byte_idx = utf8.i;
        }

        // v5.0 [MQTT-4.7.3-1]
        if (shared_filter_sep > 0 and @as(usize, shared_filter_sep) == value.len - 1) {
            return null;
        }
        // v5.0 [MQTT-4.8.2-2]
        if (shared_group_sep > 0 and shared_filter_sep == 0) {
            return null;
        }
        // v5.0 [MQTT-4.8.2-1]
        if (shared_group_sep + 1 == shared_filter_sep) {
            return null;
        }

        std.debug.assert(shared_group_sep == 0 or shared_group_sep == 6);

        return shared_filter_sep;
    }
};

test "validate topic filter" {
    const string_65535 = "a" ** 65535;
    const string_65536 = "a" ** 65536;
    const cases = [_]struct { bool, []const u8 }{
        .{ false, "abc/def" },
        .{ false, "abc/+" },
        .{ false, "abc/#" },
        .{ false, "#" },
        .{ false, "+" },
        .{ false, "+/" },
        .{ false, "+/+" },
        .{ false, "///" },
        .{ false, "//+/" },
        .{ false, "//abc/" },
        .{ false, "//+//#" },
        .{ false, "/abc/+//#" },
        .{ false, "+/abc/+" },
        .{ false, string_65535 },
        // invalid topic filter
        .{ true, "" },
        .{ true, "abc\x00def" },
        .{ true, "abc/\x00def" },
        .{ true, "++" },
        .{ true, "++/" },
        .{ true, "/++" },
        .{ true, "abc/++" },
        .{ true, "abc/++/" },
        .{ true, "#/abc" },
        .{ true, "/ab#" },
        .{ true, "##" },
        .{ true, "/abc/ab#" },
        .{ true, "/+#" },
        .{ true, "//+#" },
        .{ true, "/abc/+#" },
        .{ true, "xxx/abc/+#" },
        .{ true, "xxx/a+bc/" },
        .{ true, "x+x/abc/" },
        .{ true, "x+/abc/" },
        .{ true, "+x/abc/" },
        .{ true, "+/abc/++" },
        .{ true, "+/a+c/+" },
        .{ true, string_65536 },
    };
    for (cases) |case| {
        const result = TopicFilter.is_invalid(case[1]);
        if (case[0]) {
            try testing.expect(result == null);
        } else {
            try testing.expect(result == 0);
        }
    }
}

test "validate shared topic filter" {
    const cases = [_]struct { bool, []const u8 }{
        // valid topic filter
        .{ false, "abc/def" },
        .{ false, "abc/+" },
        .{ false, "abc/#" },
        .{ false, "#" },
        .{ false, "+" },
        .{ false, "+/" },
        .{ false, "+/+" },
        .{ false, "///" },
        .{ false, "//+/" },
        .{ false, "//abc/" },
        .{ false, "//+//#" },
        .{ false, "/abc/+//#" },
        .{ false, "+/abc/+" },
        // invalid topic filter
        .{ true, "abc\x00def" },
        .{ true, "abc/\x00def" },
        .{ true, "++" },
        .{ true, "++/" },
        .{ true, "/++" },
        .{ true, "abc/++" },
        .{ true, "abc/++/" },
        .{ true, "#/abc" },
        .{ true, "/ab#" },
        .{ true, "##" },
        .{ true, "/abc/ab#" },
        .{ true, "/+#" },
        .{ true, "//+#" },
        .{ true, "/abc/+#" },
        .{ true, "xxx/abc/+#" },
        .{ true, "xxx/a+bc/" },
        .{ true, "x+x/abc/" },
        .{ true, "x+/abc/" },
        .{ true, "+x/abc/" },
        .{ true, "+/abc/++" },
        .{ true, "+/a+c/+" },
    };
    inline for (cases) |case| {
        const result = TopicFilter.is_invalid("$share/xyz/" ++ case[1]);
        if (case[0]) {
            try testing.expect(result == null);
        } else {
            try testing.expect(result == 10);
        }
    }
}
