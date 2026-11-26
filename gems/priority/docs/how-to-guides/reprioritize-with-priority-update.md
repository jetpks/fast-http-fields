# Reprioritize with PRIORITY_UPDATE frames

## The frame in one screen

The PRIORITY_UPDATE frame carries a complete set of priority parameters for one target — unlike the Priority header field, it is hop-by-hop (§7, `rfc9218.txt:511-522`); quote: "A PRIORITY_UPDATE frame communicates a complete set of all priority parameters in the Priority Field Value field. Omitting a priority parameter is a signal to use its default value" (`rfc9218.txt:522-524`).

A browser prefetches at urgency 7, then sends urgency 0 when the user navigates (§6, `rfc9218.txt:494-505`).

The identifier: the HTTP/2 stream ID (§7.1) or the HTTP/3 stream/push ID (§7.2); the field value is the same representation as the Priority header field value (`rfc9218.txt:551,583`).

## Build an HTTP/2 PRIORITY_UPDATE payload

`Fast::Priority::H2.encode_payload(stream_id, priority)` — the 4-byte Reserved+Prioritized Stream ID word (Reserved bit 0) then the canonical field value; strict: a non-Parameters value or an ID outside 0..0x7FFFFFFF raises SerializeError (`lib/fast/priority/h2.rb:73-81,106-112`).

```ruby
require "fast/priority"

priority = Fast::Priority.parse("u=1, i")
payload = Fast::Priority::H2.encode_payload(5, priority)
payload.unpack1("H*")  # => "00000005753d312c2069"
```

## Send it through protocol-http2

Their `PriorityUpdateFrame` + `Framer` build the full frame — the 9-byte header (length, type 0x10, flags, stream ID 0) plus the payload; their frame registry knows type 0x10 (`gems/priority/test/fast/priority/interop.rb:27-35`).

```ruby
require "protocol/http2"
require "fast/priority"
require "stringio"

frame = Protocol::HTTP2::PriorityUpdateFrame.new(0)
frame.pack(5, "u=1, i")
io = StringIO.new(+"")
framer = Protocol::HTTP2::Framer.new(io)
framer.write_frame(frame)
io.string.unpack1("H*")  # => "00000a10000000000000000005753d312c2069"
io.rewind
received = framer.read_frame
received.unpack  # => [5, "u=1, i"]
```

This gem's codecs speak the payload — the framing above is the transport's job; the interop suite runs both directions against this exact peer (`gems/priority/gems.rb:24-33`).

## Decode what you receive

`Fast::Priority::H2.decode_payload(payload)` — the 31-bit stream ID (the Reserved bit masked off), the raw ASCII-8BIT field value, the §4 parse, and `#error`: §7's signal for the caller — "Failure to parse the Priority Field Value MAY be treated as a connection error. In HTTP/2, the error is of type PROTOCOL_ERROR" (`rfc9218.txt:524-526`; `lib/fast/priority/h2.rb:85-96`).

```ruby
require "fast/priority"

priority = Fast::Priority.parse("u=1, i")
payload = Fast::Priority::H2.encode_payload(5, priority)

frame = Fast::Priority::H2.decode_payload(payload)
frame.stream_id         # => 5
frame.priority.urgency  # => 1
frame.error             # => nil

bad = Fast::Priority::H2.decode_payload(("\x00\x00\x00\x05" + "!!").b)
bad.error.class         # => Fast::Priority::ParseError
bad.priority.urgency    # => 3
```

The decode never raises on field content — the connection error is your MAY, not the codec's (`lib/fast/priority/h2.rb:33-45`).

## The HTTP/3 side

The HTTP/3 payload is the QUIC variable-length Prioritized Element ID then the field value; the frame type 0xF0700 (request streams) or 0xF0701 (push streams) lives in the frame header, not the payload (§7.2, `rfc9218.txt:624-644`).

```ruby
require "fast/priority"

payload = Fast::Priority::H3.encode_payload(4, Fast::Priority.parse("u=1, i"))
payload.unpack1("H*")  # => "04753d312c2069"

frame = Fast::Priority::H3.decode_payload(payload)
frame.element_id        # => 4
frame.priority.urgency  # => 1
```

No usable Ruby HTTP/3 framing stack exists today (the published protocol-http3 releases are native extensions without a frame API), so this gem's HTTP/3 codec is verified against the RFC 9000 §16/A.1 varint vectors and §7.2's byte layouts; the HTTP/2 side carries the real peer interop. If a Ruby HTTP/3 stack gains a PRIORITY_UPDATE API, the pattern above transfers unchanged.
