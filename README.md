# mqtt-zig
Zig implementation of MQTT v3.1/v3.1.1/v5.0 codec that is **allocation free**. The code is ported from my rust library: [mqtt-proto](https://github.com/akasamq/mqtt-proto). This library is intended for both **client** and **server** usage (with `strict` protocol validation).

## Current State:
* Implemented versions
  - v3.1
  - v3.1.1
* Test Coverage: `92.2%` (by kcov)

## Example

```zig
// Encode a packet
const pkt = Packet{ .connect = Connect{
    .protocol = .V311,
    .clean_session = true,
    .keep_alive = 120,
    .client_id = Utf8View.initUnchecked("sample"),
} };
var buf: [512]u8 = undefined;
var idx: usize = 0;
try pkt.encode(buf[0..], &idx);

// Decode a packet
const read_pkt = (try Packet.decode(buf[0..])).?;
```
