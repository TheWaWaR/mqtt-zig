const std = @import("std");
const types = @import("../types.zig");
const MqttError = @import("../error.zig").MqttError;
const utils = @import("../utils.zig");
const packet = @import("./packet.zig");

const read_u16_idx = utils.read_u16_idx;
const read_string_idx = utils.read_string_idx;
const write_u16_idx = utils.write_u16_idx;
const write_bytes = utils.write_bytes;
const write_bytes_idx = utils.write_bytes_idx;

const Pid = types.Pid;
const QosPid = types.QosPid;
const TopicName = types.TopicName;
const Header = packet.Header;

/// Publish packet body type.
pub const Publish = struct {
    dup: bool,
    retain: bool,
    topic_name: TopicName,
    qos_pid: QosPid,
    payload: []const u8,

    pub fn decode(data: []const u8, header: Header, keep_data: ?[]u8) MqttError!struct { Publish, usize } {
        var remaining_len: usize = @intCast(header.remaining_len);
        var idx: usize = 0;
        var content = data[0..remaining_len];
        if (keep_data) |out| {
            if (out.len < content.len) {
                return error.OutDataBufferNotEnough;
            }
            @memcpy(out[0..remaining_len], content);
            content = out[0..remaining_len];
        }

        const topic_name = try read_string_idx(content[idx..], &idx);
        remaining_len, const overflow = @subWithOverflow(remaining_len, 2 + topic_name.bytes.len);
        if (overflow != 0) {
            return error.InvalidRemainingLength;
        }
        const qos_pid = switch (header.qos) {
            .level0 => .level0,
            .level1 => blk: {
                remaining_len, const overflow1 = @subWithOverflow(remaining_len, 2);
                if (overflow1 != 0) {
                    return error.InvalidRemainingLength;
                }
                const pid = try Pid.try_from(read_u16_idx(content[idx..], &idx));
                break :blk QosPid{ .level1 = pid };
            },
            .level2 => blk: {
                remaining_len, const overflow2 = @subWithOverflow(remaining_len, 2);
                if (overflow2 != 0) {
                    return error.InvalidRemainingLength;
                }
                const pid = try Pid.try_from(read_u16_idx(content[idx..], &idx));
                break :blk QosPid{ .level2 = pid };
            },
        };
        var payload: []const u8 = &.{};
        if (remaining_len > 0) {
            payload = content[idx .. idx + remaining_len];
            idx += remaining_len;
        }
        const value = .{
            .dup = header.dup,
            .qos_pid = qos_pid,
            .retain = header.retain,
            .topic_name = try TopicName.try_from(topic_name),
            .payload = payload,
        };
        return .{ value, idx };
    }

    pub fn encode(self: *const Publish, data: []u8, idx: *usize) void {
        write_bytes_idx(data, idx, self.topic_name.value.bytes);
        switch (self.qos_pid) {
            .level0 => {},
            .level1 => |pid| write_u16_idx(data, idx, pid.value),
            .level2 => |pid| write_u16_idx(data, idx, pid.value),
        }
        write_bytes(data, idx, self.payload);
    }

    pub fn encode_len(self: *const Publish) usize {
        var length = 2 + self.topic_name.len();
        switch (self.qos_pid) {
            .level0 => {},
            else => length += 2,
        }
        return length + self.payload.len;
    }
};
