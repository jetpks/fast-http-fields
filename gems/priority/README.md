# fast-priority

fast-priority is the RFC 9218 Extensible Priorities implementation for Ruby: the Priority HTTP header field and the HTTP/2/HTTP/3 PRIORITY_UPDATE frame payloads, built on fast-sfv.

## What it is

Implements the Priority header field (RFC 9218 §4–§5) as an RFC 9651 Dictionary consumer — urgency (`u`), incremental (`i`), and unknown-parameter passthrough — plus the PRIORITY_UPDATE frame payload codecs for HTTP/2 (§7.1) and HTTP/3 (§7.2).

The lenient parse (`parse`) answers a recipient's view and never raises on field content; the strict parse (`parse!`) tells the truth with byte offsets; `to_s` and the frame encoders are always strict. Results are frozen value objects; one runtime dependency (fast-sfv).

Pure Ruby, byte-exact binary codecs, no connection or stream state.

MIT license. Source at `https://github.com/jetpks/fast-http-fields`.

## Status

In development. The documentation pass arrives with the docs iteration, and the 0.1.0 release follows it — docs are part of the product. The field and frame surface here is complete and covered by the suite; this README is the front door, not the documentation tree.

## Installation

Not yet published. Until the first release, use the monorepo checkout:

```sh
gem "fast-priority", path: "gems/priority"   # from a fast-http-fields checkout
gem "fast-sfv"                               # the substrate, published as 0.1.1
```

Require path is `fast/priority`:

```ruby
require "fast/priority"
```

Requires Ruby >= 3.4 and RubyGems >= 3.5.3. The only runtime requirement is fast-sfv.

## Quickstart

Parse a Priority field and read it:

```ruby
require "fast/priority"

priority = Fast::Priority.parse("u=5, i")
priority.urgency      # => 5
priority.incremental  # => true
priority.to_s         # => "u=5, i"
```

An HTTP/2 PRIORITY_UPDATE payload, both directions:

```ruby
priority = Fast::Priority.parse("u=1, i")
payload = Fast::Priority::H2.encode_payload(5, priority)
# => "\x00\x00\x00\x05u=1, i" (binary)

frame = Fast::Priority::H2.decode_payload(payload)
frame.stream_id    # => 5
frame.field_value  # => "u=1, i"
frame.priority.urgency   # => 1
frame.error       # => nil
```

Carry a frame value that did not parse as a Dictionary and the decode does not raise — the failure is surfaced for the caller's RFC 9218 §7 decision (a connection error is a MAY):

```ruby
frame = Fast::Priority::H2.decode_payload("\x00\x00\x00\x05!!")
frame.error    # => #<Fast::Priority::ParseError: ...>
frame.priority # => the defaults: urgency 3, incremental false
```

The HTTP/3 side is the same shape with the QUIC variable-length element ID:

```ruby
Fast::Priority::H3.encode_payload(16384, priority).unpack1("H*")  # => "80004000753d312c2069"
Fast::Priority::H3.decode_payload("\x25u=1").element_id           # => 37
```

## The recipient's defaults

A server that receives no priority parameters acts as if the defaults were specified (§4): urgency 3, incremental false. A malformed whole field answers the same defaults — the recipient ignores what it cannot read — while a parsed field is filtered member by member: an out-of-range or wrong-typed `u` or `i` is ignored (§4's MUST), and unknown parameters pass through untouched (§4.3's extension design). A member's absence is visible on the value object rather than folded into a default, because §7 makes omission the default signal and §8 makes response omission "the server's disinterest in changing the client-provided value".

## Frame payloads, not frames

The h2 and h3 codecs start and end at the PRIORITY_UPDATE payload: the 4-byte Reserved+Prioritized Stream ID word plus the field value for HTTP/2, the QUIC varint Prioritized Element ID plus the field value for HTTP/3. The frame headers, the stream-state rules (§7.1's identifier expectations, §7.2's request- versus push-stream references), the client control stream placement, and the SETTINGS_NO_RFC7540_PRIORITIES setting (§2.1) belong to the transport stack: this gem keeps no connection or stream state, and the protocol-http2 peer that exercises the codecs in the test suite is a test-group peer, never a dependency.
