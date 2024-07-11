const std = @import("std");
const types = @import("../types.zig");
const utils = @import("../utils.zig");
const MqttError = @import("../error.zig").MqttError;
const packet = @import("./packet.zig");

const Utf8View = std.unicode.Utf8View;

const read_u8_idx = utils.read_u8_idx;
const read_u16_idx = utils.read_u16_idx;
const read_bytes_idx = utils.read_bytes_idx;
const read_string_idx = utils.read_string_idx;
const write_u8_idx = utils.write_u8_idx;
const write_u16 = utils.write_u16;
const write_u16_idx = utils.write_u16_idx;
const write_bytes = utils.write_bytes;
const write_bytes_idx = utils.write_bytes_idx;

const Header = packet.Header;
const QoS = types.QoS;
const Pid = types.Pid;
const QosPid = types.QosPid;
const Protocol = types.Protocol;
const TopicName = types.TopicName;
const TopicFilter = types.TopicFilter;
const ListView = types.ListView;

/// Subscribe packet body type.
pub const Subscribe = struct {
    pid: Pid,
    topics: FilterWithQoSListView,

    pub fn decode(data: []const u8, header: Header, keep_data: ?[]u8) MqttError!struct { Subscribe, usize } {
        var remaining_len: usize = @intCast(header.remaining_len);
        var idx: usize = 0;
        const pid = try Pid.try_from(read_u16_idx(data[idx..], &idx));
        remaining_len, const overflow = @subWithOverflow(remaining_len, 2);
        if (overflow != 0) {
            return error.InvalidRemainingLength;
        }
        if (remaining_len == 0) {
            return error.EmptySubscription;
        }

        var content = data[idx .. idx + remaining_len];
        if (keep_data) |out| {
            if (out.len < content.len) {
                return error.OutDataBufferNotEnough;
            }
            @memcpy(out[0..remaining_len], content);
            content = out[0..remaining_len];
        }
        idx = 0;

        while (remaining_len > 0) {
            const topic_filter_string = try read_string_idx(content[idx..], &idx);
            const topic_filter = try TopicFilter.try_from(topic_filter_string);
            _ = try QoS.from_u8(read_u8_idx(content[idx..], &idx));
            remaining_len, const overflow1 = @subWithOverflow(remaining_len, 3 + topic_filter.len());
            if (overflow1 != 0) {
                return error.InvalidRemainingLength;
            }
        }
        const value = .{
            .pid = pid,
            .topics = .{ .value = content },
        };
        return .{ value, 2 + idx };
    }

    pub fn encode(self: *const Subscribe, data: []u8, idx: *usize) void {
        write_u16_idx(data, idx, self.pid.value);
        write_bytes(data, idx, self.topics.value);
    }

    pub fn encode_len(self: *const Subscribe) usize {
        return 2 + self.topics.value.len;
    }
};

pub const FilterWithQoSListView = ListView(
    FilterWithQoS,
    struct {
        fn encoder(item: FilterWithQoS, data: []u8, idx: *usize) void {
            write_bytes_idx(data, idx, item.filter.value.bytes);
            write_u8_idx(data, idx, @intFromEnum(item.qos));
        }
    }.encoder,
    struct {
        fn decoder(data: []const u8, idx: *usize) FilterWithQoS {
            const topic_filter_bytes = read_bytes_idx(data[idx.*..], idx) catch unreachable;
            const topic_filter_string = Utf8View.initUnchecked(topic_filter_bytes);
            const topic_filter = TopicFilter.try_from(topic_filter_string) catch unreachable;
            const qos = QoS.from_u8(read_u8_idx(data[idx.*..], idx)) catch unreachable;
            return .{ .filter = topic_filter, .qos = qos };
        }
    }.decoder,
);

pub const FilterWithQoS = struct {
    filter: TopicFilter,
    qos: QoS,
};

/// Suback packet body type.
pub const Suback = struct {
    pid: Pid,
    topics: ReturnCodeListView,

    pub fn decode(data: []const u8, header: Header, keep_data: ?[]u8) MqttError!struct { Suback, usize } {
        var remaining_len: usize = @intCast(header.remaining_len);
        var idx: usize = 0;
        const pid = try Pid.try_from(read_u16_idx(data[idx..], &idx));
        remaining_len, const overflow = @subWithOverflow(remaining_len, 2);
        if (overflow != 0) {
            return error.InvalidRemainingLength;
        }
        var content = data[idx .. idx + remaining_len];
        if (keep_data) |out| {
            if (out.len < content.len) {
                return error.OutDataBufferNotEnough;
            }
            @memcpy(out[0..remaining_len], content);
            content = out[0..remaining_len];
        }
        idx = 0;
        while (remaining_len > 0) {
            const byte = read_u8_idx(content[idx..], &idx);
            _ = try SubscribeReturnCode.from_u8(byte);
            remaining_len -= 1;
        }
        const value = .{
            .pid = pid,
            .topics = .{ .value = content },
        };
        return .{ value, 2 + idx };
    }

    pub fn encode(self: *const Suback, data: []u8, idx: *usize) void {
        write_u16_idx(data, idx, self.pid.value);
        write_bytes(data, idx, self.topics.value);
    }

    pub fn encode_len(self: *const Suback) usize {
        return 2 + self.topics.value.len;
    }
};

pub const ReturnCodeListView = ListView(
    SubscribeReturnCode,
    struct {
        fn encoder(item: SubscribeReturnCode, data: []u8, idx: *usize) void {
            write_u8_idx(data, idx, @intFromEnum(item));
        }
    }.encoder,
    struct {
        fn decoder(data: []const u8, idx: *usize) SubscribeReturnCode {
            const byte = read_u8_idx(data[idx.*..], idx);
            const code = SubscribeReturnCode.from_u8(byte) catch unreachable;
            return code;
        }
    }.decoder,
);

/// Unsubscribe packet body type.
pub const Unsubscribe = struct {
    pid: Pid,
    topics: FilterListView,

    pub fn decode(data: []const u8, header: Header, keep_data: ?[]u8) MqttError!struct { Unsubscribe, usize } {
        var remaining_len: usize = @intCast(header.remaining_len);
        var idx: usize = 0;
        const pid = try Pid.try_from(read_u16_idx(data[idx..], &idx));
        remaining_len, const overflow = @subWithOverflow(remaining_len, 2);
        if (overflow != 0) {
            return error.InvalidRemainingLength;
        }

        var content = data[idx .. idx + remaining_len];
        if (keep_data) |out| {
            if (out.len < content.len) {
                return error.OutDataBufferNotEnough;
            }
            @memcpy(out[0..remaining_len], content);
            content = out[0..remaining_len];
        }
        idx = 0;

        while (remaining_len > 0) {
            const topic_filter_string = try read_string_idx(content[idx..], &idx);
            const topic_filter = try TopicFilter.try_from(topic_filter_string);
            remaining_len, const overflow1 = @subWithOverflow(remaining_len, 2 + topic_filter.len());
            if (overflow1 != 0) {
                return error.InvalidRemainingLength;
            }
        }
        const value = .{
            .pid = pid,
            .topics = .{ .value = content },
        };
        return .{ value, 2 + idx };
    }

    pub fn encode(self: *const Unsubscribe, data: []u8, idx: *usize) void {
        write_u16_idx(data, idx, self.pid.value);
        write_bytes(data, idx, self.topics.value);
    }

    pub fn encode_len(self: *const Unsubscribe) usize {
        return 2 + self.topics.value.len;
    }
};

pub const FilterListView = ListView(
    TopicFilter,
    struct {
        fn encoder(item: TopicFilter, data: []u8, idx: *usize) void {
            write_bytes_idx(data, idx, item.value.bytes);
        }
    }.encoder,
    struct {
        fn decoder(data: []const u8, idx: *usize) TopicFilter {
            const topic_filter_bytes = read_bytes_idx(data[idx.*..], idx) catch unreachable;
            const topic_filter_string = Utf8View.initUnchecked(topic_filter_bytes);
            const topic_filter = TopicFilter.try_from(topic_filter_string) catch unreachable;
            return topic_filter;
        }
    }.decoder,
);

/// Subscribe return code type.
pub const SubscribeReturnCode = enum(u8) {
    max_level0 = 0,
    max_level1 = 1,
    max_level2 = 2,
    failure = 0x80,

    pub fn from_u8(byte: u8) MqttError!SubscribeReturnCode {
        return switch (byte) {
            0x80 => .failure,
            0 => .max_level0,
            1 => .max_level1,
            2 => .max_level2,
            else => error.InvalidSubscribeReturnCode,
        };
    }
};
