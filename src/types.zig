const std = @import("std");
const utils = @import("utils.zig");
const consts = @import("consts.zig");
const math = std.math;
const testing = std.testing;
const Allocator = std.mem.Allocator;

const Utf8View = std.unicode.Utf8View;
const read_u16 = utils.read_u16;
const write_u8_idx = utils.write_u8_idx;
const write_bytes_idx = utils.write_bytes_idx;
const MqttError = @import("error.zig").MqttError;

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

    pub fn decode(data: []const u8) MqttError!?struct { Protocol, usize } {
        if (data.len < consts.MQTT.len + 3) {
            return null;
        }
        const name_len = read_u16(data);
        if (name_len > consts.MQISDP.len) {
            return error.InvalidProtocol;
        }
        if (data.len < name_len + 3) {
            return null;
        }
        const protocol = try Protocol.try_from(data[2 .. 2 + name_len], data[2 + name_len]);
        return .{ protocol, name_len + 3 };
    }

    pub fn name(self: Protocol) []const u8 {
        return switch (self) {
            .V310 => consts.MQISDP,
            .V311 => consts.MQTT,
            .V500 => consts.MQTT,
        };
    }

    pub fn try_from(pname: []const u8, level: u8) MqttError!Protocol {
        if (std.mem.eql(u8, pname, consts.MQTT)) {
            switch (level) {
                4 => return .V311,
                5 => return .V500,
                else => {},
            }
        }
        if (std.mem.eql(u8, pname, consts.MQISDP) and level == 3) {
            return .V310;
        }
        return error.InvalidProtocol;
    }

    pub fn encode(self: Protocol, data: []u8, idx: *usize) void {
        write_bytes_idx(data, self.name(), idx);
        const level: u8 = @intFromEnum(self);
        write_u8_idx(data, level, idx);
    }

    pub fn encode_len(self: Protocol) usize {
        return 2 + self.name().len + 1;
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
        return if (value == 0) error.ZeroPid else .{ .value = value };
    }

    /// Adding a `u16` to a `Pid` will wrap around and avoid 0.
    pub fn add(self: Pid, n: u16) Pid {
        const ov = @addWithOverflow(self.value, n);
        return if (ov[1] != 0) .{ .value = 1 } else .{ .value = ov[0] };
    }
};

/// Packet delivery [Quality of Service] level.
///
/// [Quality of Service]: http://docs.oasis-open.org/mqtt/mqtt/v3.1.1/os/mqtt-v3.1.1-os.html#_Toc398718099
pub const QoS = enum(u8) {
    /// `QoS 0`. At most once. No ack needed.
    level0 = 0,
    /// `QoS 1`. At least once. One ack needed.
    level1 = 1,
    /// `QoS 2`. Exactly once. Two acks needed.
    level2 = 2,

    pub fn from_u8(byte: u8) MqttError!QoS {
        return switch (byte) {
            0 => .level0,
            1 => .level1,
            2 => .level2,
            else => error.InvalidQos,
        };
    }
};

/// Combined [`QoS`] and [`Pid`].
///
/// Used only in [`Publish`] packets.
pub const QosPid = union(QoS) {
    level0: void,
    level1: Pid,
    level2: Pid,

    pub fn pid(self: QosPid) ?Pid {
        return switch (self) {
            .level0 => null,
            .level1 => |v| v,
            .level2 => |v| v,
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
    value: Utf8View,

    pub fn try_from(value: Utf8View) MqttError!TopicName {
        if (TopicName.is_invalid(value)) {
            return error.InvalidTopicName;
        }
        return .{ .value = value };
    }

    /// Check if the topic name is invalid.
    pub fn is_invalid(value: Utf8View) bool {
        if (value.bytes.len > @as(usize, math.maxInt(u16))) {
            return true;
        }

        var utf8 = value.iterator();
        while (utf8.nextCodepoint()) |c| {
            switch (c) {
                consts.MATCH_ONE_CHAR, consts.MATCH_ALL_CHAR, 0 => return true,
                else => {},
            }
        }
        return false;
    }

    pub fn is_shared(self: TopicName) bool {
        return std.mem.startsWith(u8, self.value.bytes, consts.SHARED_PREFIX);
    }
    pub fn is_sys(self: TopicName) bool {
        return std.mem.startsWith(u8, self.value.bytes, consts.SYS_PREFIX);
    }
};

test "validate topic name" {
    // valid topic name
    try testing.expect(!TopicName.is_invalid(try Utf8View.init("/abc/def")));
    try testing.expect(!TopicName.is_invalid(try Utf8View.init("abc/def")));
    try testing.expect(!TopicName.is_invalid(try Utf8View.init("abc")));
    try testing.expect(!TopicName.is_invalid(try Utf8View.init("/")));
    try testing.expect(!TopicName.is_invalid(try Utf8View.init("//")));
    // NOTE: Because v5.0 topic alias, we let up level to check empty topic name
    try testing.expect(!TopicName.is_invalid(try Utf8View.init("")));
    try testing.expect(!TopicName.is_invalid(try Utf8View.init("a" ** 65535)));

    // invalid topic name
    try testing.expect(TopicName.is_invalid(try Utf8View.init("#")));
    try testing.expect(TopicName.is_invalid(try Utf8View.init("+")));
    try testing.expect(TopicName.is_invalid(try Utf8View.init("/+")));
    try testing.expect(TopicName.is_invalid(try Utf8View.init("/#")));
    try testing.expect(TopicName.is_invalid(try Utf8View.init("abc/\x00")));
    try testing.expect(TopicName.is_invalid(try Utf8View.init("abc\x00def")));
    try testing.expect(TopicName.is_invalid(try Utf8View.init("abc#def")));
    try testing.expect(TopicName.is_invalid(try Utf8View.init("abc+def")));
    try testing.expect(TopicName.is_invalid(try Utf8View.init("a" ** 65536)));
}

pub const TopicFilter = struct {
    value: Utf8View,
    shared_filter_sep: u16,

    pub fn try_from(value: Utf8View) MqttError!TopicFilter {
        if (TopicFilter.is_invalid(value)) |sep| {
            return .{ .value = value, .shared_filter_sep = sep };
        } else {
            return error.InvalidTopicFilter;
        }
    }

    /// Check if the topic filter is invalid.
    ///
    ///   * The u16 returned is where the bytes index of '/' char before shared
    ///   topic filter. If null returned, the topic filter is invalid.
    pub fn is_invalid(value: Utf8View) ?u16 {
        const len = value.bytes.len;
        if (len > @as(usize, math.maxInt(u16))) {
            return null;
        }
        // v5.0 [MQTT-4.7.3-1]
        if (len == 0) {
            return null;
        }

        var last_sep = @as(usize, math.maxInt(u16)) + 1;
        var has_all = false;
        var has_one = false;
        var char_idx: usize = 0;
        var byte_idx: usize = 0;
        var shared = true;
        var shared_group_sep: u16 = 0;
        var shared_filter_sep: u16 = 0;
        var utf8 = value.iterator();
        while (utf8.nextCodepoint()) |c| {
            if (c == 0) {
                return null;
            }
            // "#" must be last char
            if (has_all) {
                return null;
            }

            if (shared and char_idx < 7 and c != consts.SHARED_PREFIX[char_idx]) {
                shared = false;
            }

            if (c == consts.LEVEL_SEP) {
                if (shared) {
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
        if (shared_filter_sep > 0 and @as(usize, shared_filter_sep) == len - 1) {
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

    pub fn is_shared(self: TopicFilter) bool {
        return self.shared_filter_sep > 0;
    }

    pub fn is_sys(self: TopicFilter) bool {
        return std.mem.startsWith(u8, self.value.bytes, consts.SYS_PREFIX);
    }

    pub fn shared_group_name(self: TopicFilter) ?[]const u8 {
        if (self.is_shared()) {
            return self.value.bytes[7..@as(usize, self.shared_filter_sep)];
        } else {
            return null;
        }
    }

    pub fn shared_filter(self: TopicFilter) ?[]const u8 {
        if (self.is_shared()) {
            return self.value.bytes[@as(usize, self.shared_filter_sep + 1)..];
        } else {
            return null;
        }
    }

    pub fn shared_info(self: TopicFilter) ?struct {
        []const u8,
        []const u8,
    } {
        if (self.is_shared()) {
            return .{
                self.value.bytes[7..@as(usize, self.shared_filter_sep)],
                self.value.bytes[@as(usize, self.shared_filter_sep + 1)..],
            };
        } else {
            return null;
        }
    }
};

pub const HeapData = struct {
    content: []u8,
    allocator: std.mem.Allocator,

    pub fn deinit(self: HeapData) void {
        self.allocator.free(self.content);
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
        const result = TopicFilter.is_invalid(try Utf8View.init(case[1]));
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
        const result = TopicFilter.is_invalid(try Utf8View.init("$share/xyz/" ++ case[1]));
        if (case[0]) {
            try testing.expect(result == null);
        } else {
            try testing.expect(result == 10);
        }
    }

    const shared_cases = [_]struct { ?struct { ?[]const u8, ?[]const u8 }, []const u8 }{
        .{ .{ null, null }, "$abc/a/b" },
        .{ .{ null, null }, "$abc/a/b/xyz/def" },
        .{ .{ null, null }, "$sys/abc" },
        .{ .{ "abc", "xyz" }, "$share/abc/xyz" },
        .{ .{ "abc", "xyz/ijk" }, "$share/abc/xyz/ijk" },
        .{ .{ "abc", "/xyz" }, "$share/abc//xyz" },
        .{ .{ "abc", "/#" }, "$share/abc//#" },
        .{ .{ "abc", "/a/x/+" }, "$share/abc//a/x/+" },
        .{ .{ "abc", "+" }, "$share/abc/+" },
        .{ .{ "你好", "+" }, "$share/你好/+" },
        .{ .{ "你好", "你好" }, "$share/你好/你好" },
        .{ .{ "abc", "#" }, "$share/abc/#" },
        .{ .{ "abc", "#" }, "$share/abc/#" },
        .{ null, "$share/abc/" },
        .{ null, "$share/abc" },
        .{ null, "$share/+/y" },
        .{ null, "$share/+/+" },
        .{ null, "$share//y" },
        .{ null, "$share//+" },
    };
    for (shared_cases) |case| {
        const content = try Utf8View.init(case[1]);
        const result = TopicFilter.is_invalid(content);
        if (case[0] == null) {
            try testing.expect(result == null);
        } else {
            const filter = try TopicFilter.try_from(content);
            const info_opt = case[0].?;
            if (info_opt[0] == null) {
                try testing.expect(filter.shared_group_name() == null);
                try testing.expect(filter.shared_filter() == null);
            } else {
                try testing.expect(std.mem.eql(u8, filter.shared_group_name().?, info_opt[0].?));
                try testing.expect(std.mem.eql(u8, filter.shared_filter().?, info_opt[1].?));
                const info = filter.shared_info().?;
                try testing.expect(std.mem.eql(u8, info[0], info_opt[0].?));
                try testing.expect(std.mem.eql(u8, info[1], info_opt[1].?));
            }
        }
    }
}

test "all decls" {
    testing.refAllDecls(Protocol);
    testing.refAllDecls(QoS);
    testing.refAllDecls(Pid);
    testing.refAllDecls(QosPid);
    testing.refAllDecls(TopicName);
    testing.refAllDecls(TopicFilter);
}
