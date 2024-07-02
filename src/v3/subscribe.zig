const std = @import("std");
const types = @import("../types.zig");
const utils = @import("../utils.zig");
const MqttError = @import("../error.zig").MqttError;
const packet = @import("./packet.zig");

const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;

const read_u8_idx = utils.read_u8_idx;
const read_u16_idx = utils.read_u16_idx;
const read_string_idx = utils.read_string_idx;
const write_u8_idx = utils.write_u8_idx;
const write_u16_idx = utils.write_u16_idx;
const write_bytes_idx = utils.write_bytes_idx;

const Header = packet.Header;
const QoS = types.QoS;
const Pid = types.Pid;
const QosPid = types.QosPid;
const Protocol = types.Protocol;
const TopicName = types.TopicName;
const TopicFilter = types.TopicFilter;
const HeapData = types.HeapData;

/// Subscribe packet body type.
pub const Subscribe = struct {
    pid: Pid,
    topics: ArrayList(FilterWithQoS),

    heap_data: HeapData,

    pub fn decode(data: []const u8, header: Header, allocator: Allocator) MqttError!struct { Subscribe, usize } {
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

        const content = try allocator.alloc(u8, remaining_len);
        @memcpy(content, data[idx .. idx + remaining_len]);
        const heap_data = .{ .content = content, .allocator = allocator };
        idx = 0;

        var topics = try ArrayList(FilterWithQoS).initCapacity(allocator, 1);
        while (remaining_len > 0) {
            const topic_filter_string = try read_string_idx(content[idx..], &idx);
            const topic_filter = try TopicFilter.try_from(topic_filter_string);
            const qos = try QoS.from_u8(read_u8_idx(content[idx..], &idx));
            remaining_len, const overflow1 = @subWithOverflow(remaining_len, 3 + topic_filter.len());
            if (overflow1 != 0) {
                return error.InvalidRemainingLength;
            }
            try topics.append(.{ .filter = topic_filter, .qos = qos });
        }
        const value = .{
            .pid = pid,
            .topics = topics,
            .heap_data = heap_data,
        };
        return .{ value, 2 + idx };
    }

    pub fn encode(self: *const Subscribe, data: []u8, idx: *usize) void {
        write_u16_idx(data, self.pid.value, idx);
        for (self.topics.items) |topic| {
            write_bytes_idx(data, topic.filter.value.bytes, idx);
            write_u8_idx(data, @intFromEnum(topic.qos), idx);
        }
    }

    pub fn encode_len(self: *const Subscribe) usize {
        var length: usize = 2;
        for (self.topics.items) |topic| {
            length += 3;
            length += topic.filter.len();
        }
        return length;
    }

    pub fn deinit(self: *Subscribe) void {
        self.heap_data.deinit();
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

    pub fn encode(_: *const Suback, _: []u8, _: *usize) void {}

    pub fn encode_len(_: *const Suback) usize {
        return 0;
    }
};

/// Unsubscribe packet body type.
pub const Unsubscribe = struct {
    pid: Pid,
    topics: ArrayList(TopicFilter),

    pub fn decode(_: []const u8, _: Header) MqttError!struct { Unsubscribe, usize } {
        return error.InvalidRemainingLength;
    }

    pub fn encode(_: *const Unsubscribe, _: []u8, _: *usize) void {}

    pub fn encode_len(_: *const Unsubscribe) usize {
        return 0;
    }
};

/// Subscribe return code type.
pub const SubscribeReturnCode = enum(u8) {
    max_level0 = 0,
    max_level1 = 1,
    max_level2 = 2,
    failure = 0x80,
};
