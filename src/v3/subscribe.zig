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
const Allocated = types.Allocated;

/// Subscribe packet body type.
pub const Subscribe = struct {
    pid: Pid,
    topics: ArrayList(FilterWithQoS),

    allocated: ?Allocated = null,

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
        const allocated = .{ .content = content, .allocator = allocator };
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
            .allocated = allocated,
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

    pub fn deinit(self: Subscribe) void {
        if (self.allocated) |allocated| {
            allocated.deinit();
        }
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

    pub fn decode(data: []const u8, header: Header, allocator: Allocator) MqttError!struct { Suback, usize } {
        var remaining_len: usize = @intCast(header.remaining_len);
        var idx: usize = 0;
        const pid = try Pid.try_from(read_u16_idx(data[idx..], &idx));
        remaining_len, const overflow = @subWithOverflow(remaining_len, 2);
        if (overflow != 0) {
            return error.InvalidRemainingLength;
        }
        var topics = try ArrayList(SubscribeReturnCode).initCapacity(allocator, 1);
        while (remaining_len > 0) {
            const byte = read_u8_idx(data[idx..], &idx);
            try topics.append(try SubscribeReturnCode.from_u8(byte));
            remaining_len -= 1;
        }
        const value = .{ .pid = pid, .topics = topics };
        return .{ value, idx };
    }

    pub fn encode(self: *const Suback, data: []u8, idx: *usize) void {
        write_u16_idx(data, self.pid.value, idx);
        for (self.topics.items) |topic| {
            write_u8_idx(data, @intFromEnum(topic), idx);
        }
    }

    pub fn encode_len(self: *const Suback) usize {
        return 2 + self.topics.items.len;
    }

    pub fn deinit(self: Suback) void {
        self.topics.deinit();
    }
};

/// Unsubscribe packet body type.
pub const Unsubscribe = struct {
    pid: Pid,
    topics: ArrayList(TopicFilter),

    pub fn decode(data: []const u8, header: Header, allocator: Allocator) MqttError!struct { Unsubscribe, usize } {
        var remaining_len: usize = @intCast(header.remaining_len);
        var idx: usize = 0;
        const pid = try Pid.try_from(read_u16_idx(data[idx..], &idx));
        remaining_len, const overflow = @subWithOverflow(remaining_len, 2);
        if (overflow != 0) {
            return error.InvalidRemainingLength;
        }

        var topics = try ArrayList(TopicFilter).initCapacity(allocator, 1);
        while (remaining_len > 0) {
            const topic_filter_string = try read_string_idx(data[idx..], &idx);
            const topic_filter = try TopicFilter.try_from(topic_filter_string);
            remaining_len, const overflow1 = @subWithOverflow(remaining_len, 2 + topic_filter.len());
            if (overflow1 != 0) {
                return error.InvalidRemainingLength;
            }
            try topics.append(topic_filter);
        }
        const value = .{ .pid = pid, .topics = topics };
        return .{ value, idx };
    }

    pub fn encode(self: *const Unsubscribe, data: []u8, idx: *usize) void {
        write_u16_idx(data, self.pid.value, idx);
        for (self.topics.items) |topic| {
            write_bytes_idx(data, topic.value.bytes, idx);
        }
    }

    pub fn encode_len(self: *const Unsubscribe) usize {
        var length: usize = 2;
        for (self.topics.items) |topic| {
            length += 2;
            length += topic.len();
        }
        return length;
    }

    pub fn deinit(self: Unsubscribe) void {
        self.topics.deinit();
    }
};

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
