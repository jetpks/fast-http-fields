# Your first Priority field

You will read and write HTTP priority signals (RFC 9218) with `Fast::Priority` in about ten minutes.

## What you will learn

Parse a Priority field and read urgency, incremental, and unknown parameters; build a value and emit the canonical field; know what the defaults are and meet the strict error.

Assumes Ruby >= 3.4 and familiarity with HTTP request/response basics (`fast-priority.gemspec:20`).

## Set up

```sh
gem install fast-priority
```

```ruby
require "fast/priority"
```

## Parse the request priority

The Priority field is an RFC 9651 Dictionary: keys are priority parameters, `u` is urgency (Integer 0..7, default 3), `i` is incremental (Boolean, default false) (RFC 9218 §5 at `rfc9218.txt:474-488`; §4.1 at 346-350; §4.2 at 376-383).

`Fast::Priority.parse(input)` returns a frozen `Fast::Priority::Parameters`; a String is one field value, an Array is the field's lines (`lib/fast/priority/field.rb:197,231`).

The readers answer the RFC's defaults when a member is absent (`lib/fast/priority/parameters.rb:70-77`).

```ruby
require "fast/priority"

priority = Fast::Priority.parse("u=2, i")
priority.urgency      # => 2
priority.incremental  # => true

Fast::Priority.parse("u=2").incremental  # => false
```

Urgency 0 is highest precedence, 7 is reserved for background tasks such as software updates (§4.1, `rfc9218.txt:348-350,372`).

## Unknown parameters pass through

RFC 9218 is extensible by design: unknown priority parameters MUST be ignored by recipients that do not understand them (§4/§4.3, `rfc9218.txt:340-344,409-415`); this gem hands them to you as parsed (`lib/fast/priority/parameters.rb:83,157-167`).

```ruby
require "fast/priority"

priority = Fast::Priority.parse("u=1, i, foo=bar")
priority.unknown.keys           # => ["foo"]
priority.unknown["foo"].value         # => "bar"
priority.unknown["foo"].value.class  # => Fast::SFV::Token
priority.to_s                   # => "u=1, i, foo=bar"
```

The value is a `Fast::SFV::Token` — a String subclass — because the wire type says so; `== "bar"` is true in both directions. See the fast-sfv docs at `https://github.com/jetpks/fast-http-fields/tree/main/gems/sfv/docs`.

## Build a value and emit it

`Fast::Priority::Parameters.new(urgency:, incremental:, unknown:)` — every keyword optional; an omitted one means the member is absent (the reader still answers the default, `to_s` omits the member) (`lib/fast/priority/parameters.rb:57-68`).

Construction validates, like every emit path: urgency must be an Integer 0..7, incremental a Boolean, unknown a Hash of SFV Items/InnerLists — anything else raises `Fast::Priority::SerializeError` before anything reaches the wire (`lib/fast/priority/parameters.rb:169-213`).

`#to_s` answers the canonical RFC 9651 §4.1.2 Dictionary form; `""` when nothing is held — a sender omits the field entirely (`lib/fast/priority/parameters.rb:89-93`).

```ruby
require "fast/priority"

priority = Fast::Priority::Parameters.new(urgency: 2, incremental: true)
priority.to_s  # => "u=2, i"

Fast::Priority::Parameters.new.to_s  # => ""
```

## When the field is wrong

`parse` never raises on field content: malformed input answers the defaults (`lib/fast/priority/field.rb:133-144`).

`parse!` is the strict view: it raises `Fast::Priority::ParseError` with `#offset`, the byte position in the combined field value (`lib/fast/priority/field.rb:210-218`).

```ruby
require "fast/priority"

begin
  Fast::Priority.parse!("u=9")
rescue Fast::Priority::ParseError => e
  e.offset  # => 2
end
```

When you only need a yes/no: `Fast::Priority.valid?("u=9")  # => false` (`lib/fast/priority/field.rb:221-228`).

## Where next

- [Parse request priority in Rack](../how-to-guides/parse-request-priority.md) — read a Priority header from a Rack env
- [Emit Priority from a server](../how-to-guides/emit-priority-from-a-server.md) — build and send a Priority response
- [Reprioritize with PRIORITY_UPDATE frames](../how-to-guides/reprioritize-with-priority-update.md) — the frame payload codecs
- [Handle malformed or absent Priority](../how-to-guides/handle-malformed-priority.md) — the full malformed story
- [API reference](../reference/api.md) and [Frame payload codecs](../reference/frames.md)
