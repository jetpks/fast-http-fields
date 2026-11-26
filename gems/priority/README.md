# fast-priority

fast-priority is the RFC 9218 Extensible Priorities implementation for Ruby: the Priority HTTP field and the HTTP/2/HTTP/3 PRIORITY_UPDATE frame payloads, built on fast-sfv.

## What it is

Implements RFC 9218: the Priority header field (§4–§5) as an RFC 9651 Dictionary consumer — urgency (`u`), incremental (`i`), unknown-parameter passthrough — plus the PRIORITY_UPDATE frame payload codecs for HTTP/2 (§7.1) and HTTP/3 (§7.2) (`lib/fast/priority.rb:18-21,46-53`).

The lenient parse (`parse`) answers a recipient's view and never raises on field content; the strict parse (`parse!`) tells the truth with byte offsets; `to_s` and the frame encoders are always strict; results are frozen value objects; one runtime dependency (fast-sfv) (`lib/fast/priority.rb:24-45`; `fast-priority.gemspec:47`).

Pure Ruby, byte-exact binary codecs, no connection or stream state (`lib/fast/priority.rb:55,64`).

MIT license; source at `https://github.com/jetpks/fast-http-fields` (`fast-priority.gemspec:19-20`).

## Installation

```sh
gem install fast-priority
```

In a Gemfile:

```ruby
gem "fast-priority"
```

Require path is `fast/priority`:

```ruby
require "fast/priority"
```

Requires Ruby >= 3.4 and RubyGems >= 3.5.3; the only runtime requirement is fast-sfv (`fast-priority.gemspec:22-23,47`).

## Quickstart

Parse a Priority field and read it:

```ruby
require "fast/priority"

priority = Fast::Priority.parse("u=5, i")
priority.urgency      # => 5
priority.incremental  # => true
priority.to_s         # => "u=5, i"

Fast::Priority.parse("!!").urgency  # => 3
```

The malformed line never raises — a recipient that cannot read the field answers the §4 defaults (urgency 3, incremental false).

An HTTP/2 PRIORITY_UPDATE payload, both directions:

```ruby
require "fast/priority"

payload = Fast::Priority::H2.encode_payload(5, Fast::Priority.parse("u=1, i"))
payload.unpack1("H*")  # => "00000005753d312c2069"

frame = Fast::Priority::H2.decode_payload(payload)
frame.stream_id    # => 5
frame.field_value  # => "u=1, i"
frame.error        # => nil
```

Next: the [tutorial](docs/tutorials/priority-field.md) for the guided path.

## The recipient defaults

- A server that receives no priority parameters acts as if the defaults were specified: urgency 3, incremental false (§4; RFC 9218 §4.1 "The default is 3" at `rfc9218.txt:350`; §4.2 at 383).
- A malformed whole field answers the same defaults — the recipient ignores what it cannot read — while a parsed field is filtered member by member: out-of-range or wrong-typed `u`/`i` is ignored, unknown parameters pass through untouched (§4's MUST-ignore, `rfc9218.txt:340-344`).
- A member's absence is visible on the value object rather than folded into a default (§7's omission-is-default signal and §8's response omission semantics, `rfc9218.txt:523-524,694-696`).

See [Handle malformed or absent Priority](docs/how-to-guides/handle-malformed-priority.md) and [Why malformed input answers the defaults](docs/explanation/defaults-on-malformed.md).

## Frame payloads, not frames

- The h2 and h3 codecs start and end at the PRIORITY_UPDATE payload: the 4-byte Reserved+Prioritized Stream ID word plus the field value for HTTP/2, the QUIC varint Prioritized Element ID plus the field value for HTTP/3 (`lib/fast/priority/h2.rb:16-22`; `lib/fast/priority/h3.rb:11-17`).
- Frame headers, stream-state rules, control-stream placement, and SETTINGS_NO_RFC7540_PRIORITIES are the transport's: this gem keeps no connection or stream state (`lib/fast/priority.rb:56-58`).

See [Frame payload codecs](docs/reference/frames.md) and [How the priority scheme binds to HTTP/2 and HTTP/3](docs/explanation/h2-h3-bindings.md).

## Documentation

Current release 0.1.0; changelog at [CHANGELOG.md](CHANGELOG.md).

### Tutorial

- [Your first Priority field](docs/tutorials/priority-field.md) — One guided path: parse a request's priority, read it, meet the unknown passthrough, build and emit a value, meet the defaults and the strict error.

### How-to guides

- [Parse request priority in Rack](docs/how-to-guides/parse-request-priority.md) — Read a Priority header in a Rack-shaped env, parse it, handle absence and multiple lines, know what to schedule on.
- [Emit Priority from a server](docs/how-to-guides/emit-priority-from-a-server.md) — Build a Parameters, emit the canonical field, merge client and server signals per §8, set the response header.
- [Reprioritize with PRIORITY_UPDATE frames](docs/how-to-guides/reprioritize-with-priority-update.md) — Build, send, and decode h2 PRIORITY_UPDATE payloads with protocol-http2; the h3 side with hand-built payloads.
- [Handle malformed or absent Priority](docs/how-to-guides/handle-malformed-priority.md) — What malformed and absent input answer, member-level ignoring, the strict view, and the frame payload's error signal.

### Reference

- [API reference](docs/reference/api.md) — The complete field surface: every method, class, error, input/output shape, with signatures and return types.
- [Frame payload codecs](docs/reference/frames.md) — The frame payload codecs: constants, byte layouts, the Frame results, the varint, the error contract, and how the codecs are verified.

### Explanation

- [Why malformed input answers the defaults](docs/explanation/defaults-on-malformed.md) — Why §4's recipient contract answers defaults on malformed input, why absence stays visible, and the three-failure taxonomy.
- [How the priority scheme binds to HTTP/2 and HTTP/3](docs/explanation/h2-h3-bindings.md) — Why the scheme exists (replacing RFC 7540 priorities), the SETTINGS_NO_RFC7540_PRIORITIES story, end-to-end vs hop-by-hop, and the transport-owned boundary.
- [Performance and allocation budgets](docs/explanation/performance.md) — How the paths stay allocation-lean; the both-mode benchmark tables and the allocation budgets, with methodology and caveats.
