# The substrate: Structured Field Values

One grammar underlies all five gems. This page explains what Structured Field Values are, why the family bet on a single substrate, and what that buys.

## The problem the RFC solved

HTTP fields used to be free-form strings, so every new field invented its own syntax and every implementation its own parser, and the parsers drifted — subtly different workarounds for the same corner cases.

RFC 9651 — Structured Field Values — defines a small type system (integers, decimals, strings, tokens, byte sequences, booleans, dates, display strings, and lists, dictionaries and parameterized items built from them) plus exact parse and serialize algorithms, so a field spec declares types instead of syntax and every implementation gets the same parser. RFC 9651 obsoleted RFC 8941.

## What the gems get from it

The substrate beneath a dependent:

```ruby
require "fast/sfv"
require "fast/priority"

dict = Fast::SFV.parse_dict("u=1, i")
dict["u"].value  # => 1

priority = Fast::Priority.parse("u=1, i")
priority.urgency  # => 1
```

The same `u=1, i` — once as a generic dictionary, once as a Priority field. The field gem adds its RFC's semantics on top of the same grammar.

Three services the substrate provides:

The grammar — the whole family's error taxonomy inherits RFC 9651's intentional strictness, so implementations cannot drift into workarounds.

The canonical serialization — every gem's `to_s` is the same emit engine, so outputs round-trip and every reader sees the same bytes.

The field-line combining — every entry point accepts a String or an Array of lines, combining them into one comma-separated value before parsing (parsers combine all field lines in the same section — header or trailer — that match the field name into one value).

The type tags: the Ruby type is the wire-type tag — a `Fast::SFV::Token` is a token, an ASCII-8BIT `String` is a byte sequence — so day-one idioms like `field["sha-256"] == Digest::SHA256.digest(body)` hold bytewise (see [wire-type tag](../../gems/sfv/docs/explanation/wire-type-tag.md)).

## Why one gem owns it

The grammar is implemented once, not five times. Each dependent declares exactly one runtime dependency (`fast-sfv`) and adds only its RFC's constraints and recipient rules on top. No grammar drift between the gems, no version skew inside one gem's parse and emit. fast-sfv itself depends on nothing.

The [family map](../reference/family-map.md) carries the whole shape.

## Going deeper

The technical layer starts here:

- The [sfv README](../../gems/sfv/README.md)
- Its [tutorial](../../gems/sfv/docs/tutorials/structured-fields.md)
- Its [conformance page](../../gems/sfv/docs/reference/conformance.md) — the vendored official httpwg corpus that referees the grammar
- Its [strictness explanation](../../gems/sfv/docs/explanation/strictness.md)

