# Frame payload codecs

The definitive page for `Fast::Priority::H2` and `Fast::Priority::H3`.

## Scope

Payload-level codecs: the bytes after the frame header, both transports (`lib/fast/priority/h2.rb:16-22`; `lib/fast/priority/h3.rb:11-17`).

The transport owns the rest — the HTTP/2 9-byte header (the header Stream Identifier MUST be zero, §7.1, `rfc9218.txt:555-557`), the HTTP/3 type/length varints and the client-control-stream placement (§7.2, `rfc9218.txt:628`), the stream-state rules, and every SETTINGS decision; no connection or stream state here (`lib/fast/priority.rb:56-58`).

## HTTP/2 — Fast::Priority::H2

Constants: `FRAME_TYPE = 0x10` (§7.1, `rfc9218.txt:547-548`; IANA at 995-998), `MAX_STREAM_ID = 0x7FFF_FFFF`, `PREFIX_SIZE = 4` (`lib/fast/priority/h2.rb:33-39`).

The payload layout (Figure 1's tail), with §7.1's own payload prose quoted: "Prioritized Stream ID: A 31-bit stream identifier for the stream that is the target of the priority update" and "Priority Field Value: The priority update value in ASCII text, encoded using Structured Fields. This is the same representation as the Priority header field value" (`rfc9218.txt:577-587`); the Reserved(1)+Prioritized Stream ID(31) as one big-endian 32-bit word — Reserved written 0 on send, masked off on receipt — then the Priority Field Value (`lib/fast/priority/h2.rb:85-96`).

`encode_payload(stream_id, priority)` → ASCII-8BIT String; strict: SerializeError for a non-Parameters priority or an ID outside 0..0x7FFFFFFF (`lib/fast/priority/h2.rb:73-81`).

`decode_payload(payload)` → a frozen `H2::Frame` with `stream_id` (31-bit), `field_value` (ASCII-8BIT), `priority` (the §4 parse), `error` (§7's signal, nil when the value parsed); TypeError for a non-String payload; ParseError at the payload's byte size for a payload shorter than the 4-byte word (`lib/fast/priority/h2.rb:85-96,114-118`).

```ruby
require "fast/priority"

Fast::Priority::H2.encode_payload(5, Fast::Priority.parse("u=1, i")).unpack1("H*")
# => "00000005753d312c2069"
Fast::Priority::H2.decode_payload(("\x80\x00\x00\x05" + "u=1").b).stream_id  # => 5
```

## HTTP/3 — Fast::Priority::H3

Constants: `REQUEST_TYPE = 0xF0700`, `PUSH_TYPE = 0xF0701` (§7.2, `rfc9218.txt:624-627`), `MAX_ELEMENT_ID = (1 << 62) - 1` (RFC 9000 §16 Table 4), `VARINT_MASK = 0x3F` (`lib/fast/priority/h3.rb:31-40`).

The payload layout (Figure 2's tail): the Prioritized Element ID as a QUIC variable-length integer (RFC 9000 §16 — "The stream ID or push ID that is the target of the priority update", `rfc9218.txt:644`), then the Priority Field Value (`lib/fast/priority/h3.rb:11-17`).

The varint discipline: encode emits the minimal form; decode reads any of the four forms (RFC 9000 §16's only must-be-minimal field is the Frame Type, and the Element ID is not it; Appendix A.1's fold) (`lib/fast/priority/h3.rb:111-133`).

`encode_payload(element_id, priority)` / `decode_payload(payload)` — the same contract shapes as H2 (62-bit bound; empty payload or a truncated varint raises ParseError at the payload's byte size) (`lib/fast/priority/h3.rb:74-108,137-157`).

```ruby
require "fast/priority"

Fast::Priority::H3.encode_payload(16384, Fast::Priority.parse("u=1, i")).unpack1("H*")
# => "80004000753d312c2069"
Fast::Priority::H3.decode_payload("\x25u=1".b).element_id  # => 37
Fast::Priority::H3.decode_payload(("\x80\x00\x0f\xb9" + "u=1").b).element_id  # => 4025
Fast::Priority::H3.decode_payload(
  Fast::Priority::H3.encode_payload((1 << 62) - 1, Fast::Priority.parse("u=0"))
).element_id  # => 4611686018427387903
```

## The error contract

§7's signal, quoted: "Failure to parse the Priority Field Value MAY be treated as a connection error. In HTTP/2, the error is of type PROTOCOL_ERROR; in HTTP/3, the error is of type H3_GENERAL_PROTOCOL_ERROR" (`rfc9218.txt:524-527`).

The MAY is the caller's; a parsed-but-ignored member is not a failure; `#priority` is the defaults only when `#error` is set (`lib/fast/priority/h2.rb:33-45`).

```ruby
require "fast/priority"

frame = Fast::Priority::H2.decode_payload(("\x00\x00\x00\x05" + "!!").b)
frame.error.class      # => Fast::Priority::ParseError
frame.error.offset     # => 0
frame.priority.urgency # => 3
```

## How the codecs are verified

The vectors: RFC 9218's own byte layouts (Figures 1/2) and RFC 9000 §16/A.1's varint examples, frozen in the suite (`test/fast/priority/frames.rb:16-160`).

The peer interop: protocol-http2 0.29.2 as a test-group peer in the gem's own bundle — both directions, their framer's full-frame byte form, the FRAMES registry — 6/6 its (`test/fast/priority/interop.rb`; `gems/priority/gems.rb:24-33`).

The HTTP/3 side: vector-verified — no usable Ruby HTTP/3 framing stack exists (the published protocol-http3 releases are native extensions without a frame API; the HTTP/2 peer carries the real interop).

The suite totals at writing: 3016 passed / 4482 assertions, every gem's suites green together at the monorepo root.
