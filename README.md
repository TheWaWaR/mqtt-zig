# mqtt-zig
Zig implementation of MQTT v3.1/v3.1.1/v5.0 codec. The code is ported from my rust library: [mqtt-proto](https://github.com/akasamq/mqtt-proto). This library is intended for both **client** and **server** usage (with `strict` protocol validation).

## Current State:
* Implemented versions
  - v3.1
  - v3.1.1
* Test Coverage: `92.2%` (by kcov)

## Example

```zig
// Encode a packet
const pkt = Packet{
    .connect = Connect{
        .protocol = .V311,
        .clean_session = true,
        .keep_alive = 120,
        .client_id = Utf8View.initUnchecked("sample"),
    },
};
const remaining_len = (try pkt.encode_len()).remaining_len;
var buf: [512]u8 = undefined;
var idx: usize = 0;
pkt.encode(remaining_len, write_buf[0..], &idx);

// Decode a packet
const allocator = std.testing.allocator;
const header, const header_len = (try Header.decode(buf[0..])).?;
const read_pkt, const read_idx = (try Packet.decode(buf[header_len..], header, allocator)).?;
defer read_pkt.deinit();
```
