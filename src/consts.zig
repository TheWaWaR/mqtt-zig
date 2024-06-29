/// Character used to separate each level within a topic tree and provide a hierarchical structure.
pub const LEVEL_SEP: u8 = '/';
/// Wildcard character that matches only one topic level.
pub const MATCH_ONE_CHAR: u8 = '+';
/// Wildcard character that matches any number of levels within a topic.
pub const MATCH_ALL_CHAR: u8 = '#';

/// System topic prefix
pub const SYS_PREFIX: []const u8 = "$SYS/";
/// Shared topic prefix
pub const SHARED_PREFIX: []const u8 = "$share/";

pub const MQISDP: []const u8 = "MQIsdp";
pub const MQTT: []const u8 = "MQTT";
