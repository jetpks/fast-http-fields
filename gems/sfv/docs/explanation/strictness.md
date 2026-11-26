# Why parsing and serialization are strict

## The RFC's own demand

RFC 9651 §1.1: strict, step-by-step algorithms; the only error handling is to fail the entire operation; tolerance would make interoperability worse.

RFC 9651 §1.2: behavior indistinguishable from the algorithms.

fast-sfv cites both in the error definitions — strictness is not a preference but the specification's requirement.

## Three failures, three causes

- **`TypeError` (parse side only)** — a wrong input type is a caller bug, not field content: `a String or an Array of String field lines is required`.

```ruby
require "fast/sfv"

Fast::SFV.parse_item(42)  # => raises TypeError
```

- **`ParseError`** — field content that is not a Structured Field Value of the asked shape; strictness leaves no lenient reading to fall back to.

```ruby
require "fast/sfv"

Fast::SFV.parse_item("foo bar")  # => raises Fast::SFV::ParseError
```

- **`SerializeError` (the whole emit path)** — the wrongness is in the value tree being sent: wrong types, wrong shapes, out-of-range values, invalid key or string content — which is field content, not a caller protocol bug, so `TypeError` never appears on emit.

```ruby
require "fast/sfv"

Fast::SFV.serialize_item(:foo)  # => raises Fast::SFV::SerializeError
```

Why the split matters: a rescue of `Fast::SFV::Error` handles the two field-content failures while caller bugs surface loudly.

```ruby
require "fast/sfv"

begin
  Fast::SFV.parse_item(input)
rescue Fast::SFV::Error => e
  # ParseError or SerializeError — field content problem
end
# TypeError is not caught — caller bug
```

## Offsets, not booleans

Both errors carry a byte offset: `ParseError#offset` into the combined input (where the parse stopped), `SerializeError#offset` into the output built so far (where the emit stopped) — positions a diagnostic can point at.

The `valid_*?` mirrors exist for the yes/no question and deliberately discard the position.

```ruby
require "fast/sfv"

Fast::SFV.valid_item?("foo bar")  # => false — no offset, no value
begin
  Fast::SFV.parse_item("foo bar")
rescue Fast::SFV::ParseError => e
  e.offset  # => 4 — where to look
end
```

See [Diagnose a rejected field value](../how-to-guides/diagnose-failures.md).

## What strictness buys

The gem is the family substrate — every other fast-http-fields gem parses and emits through Structured Field Values, so one strict layer carries the conformance burden for the family.

The vendored httpwg corpus referees every grammar edge. See [Conformance and the httpwg corpus](../reference/conformance.md).

No lenient mode, no per-field workarounds: an error in one party's appended value is likely to fail the entire field value — the RFC's own warning (RFC 9651 §1.1).
