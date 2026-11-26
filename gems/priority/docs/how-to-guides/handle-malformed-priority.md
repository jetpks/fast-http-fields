# Handle malformed or absent Priority

## The recipient contract

§4's rule, quoted: "Receivers parse the Dictionary as described in Section 4.2 of [STRUCTURED-FIELDS]. Where the Dictionary is successfully parsed, this document places the additional requirement that unknown priority parameters, priority parameters with out-of-range values, or values of unexpected types MUST be ignored" (`rfc9218.txt:340-344`).

The SHOULD-defaults sentence, quoted: "When receiving an HTTP request that does not carry these priority parameters, a server SHOULD act as if their default values were specified" — with that wording at `rfc9218.txt:332-334`.

## parse never raises on content

Malformed whole field → the defaults object (no member held, `to_s` "") (`lib/fast/priority/field.rb:133-144`).

```ruby
require "fast/priority"

Fast::Priority.parse("!!").urgency      # => 3
Fast::Priority.parse("!!").incremental  # => false
Fast::Priority.parse("!!").to_s         # => ""
```

The quoted SHOULD-defaults sentence above is why: absence and malformedness answer the same way.

## Member-level ignoring

A parsed field is filtered member by member: an out-of-range or wrong-typed `u` or `i` is dropped — never re-emitted, so the recipient never puts garbage back on the wire — unknown members pass through as parsed (`lib/fast/priority/field.rb:164-186`).

```ruby
require "fast/priority"

Fast::Priority.parse("u=9").urgency     # => 3
Fast::Priority.parse("u=fast").urgency  # => 3
Fast::Priority.parse("u=1, i, foo=bar").to_s  # => "u=1, i, foo=bar"
```

The quoted MUST-ignore sentence above is the rule: out-of-range and wrong-typed values of unexpected types MUST be ignored.

## When you want the truth

`parse!` — the strict view: the Dictionary failure wrapped with its message and byte offset; §4 semantic errors positioned at the effective member's value (`lib/fast/priority/field.rb:210-218,237-262`).

```ruby
require "fast/priority"

begin
  Fast::Priority.parse!("u=1, u=9")
rescue Fast::Priority::ParseError => e
  e.offset  # => 7
end
```

`valid?` — the boolean mirror, false for malformed content, §4 violations, and wrong input types alike:

```ruby
require "fast/priority"

Fast::Priority.valid?("u=1, i")  # => true
Fast::Priority.valid?("u=9")     # => false
Fast::Priority.valid?("!!")      # => false
```

## The frame payload signal

The frame decoders surface the parse failure on `#error` for the caller's §7 MAY (a connection error in HTTP/2 is PROTOCOL_ERROR, in HTTP/3 H3_GENERAL_PROTOCOL_ERROR, `rfc9218.txt:524-527`); a parsed-but-ignored member is not a failure. See [Reprioritize with PRIORITY_UPDATE frames](reprioritize-with-priority-update.md) and [Why malformed input answers the defaults](../explanation/defaults-on-malformed.md).
