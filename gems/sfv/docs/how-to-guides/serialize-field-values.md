# Serialize a field value

## Serialize what you parsed

`Fast::SFV.serialize_item(item)` / `serialize_list(list)` / `serialize_dict(dict)` — arity 1 each.

The answer is the canonical RFC 9651 §4.1 form as a fresh, mutable US-ASCII String the caller owns; a second call returns a different object.

`serialize_item(item)` answers exactly `item.to_s`; `InnerList#to_s`, `Date#to_s`, `DisplayString#to_s` are the same emit.

```ruby
require "fast/sfv"

dict = Fast::SFV.parse_dict("a=1, b;foo=bar, c=(1 2)")
Fast::SFV.serialize_dict(dict)  # => "a=1, b;foo=bar, c=(1 2)"
Fast::SFV.serialize_dict(dict).encoding  # => #<Encoding:US-ASCII>

item = Fast::SFV.parse_item("2; a=1")
Fast::SFV.serialize_item(item) == item.to_s  # => true
```

## Build values by hand

`Fast::SFV::Item.new(value, params)`; `Fast::SFV::InnerList.new(items, params)`; `Fast::SFV::Token.new(content)`; `Fast::SFV::Date.new(integer)`; `Fast::SFV::DisplayString.new(string)` — every constructor freezes the instance.

`Token.new` validates the whole token grammar at the boundary: `ArgumentError` for content outside it, `TypeError` for a non-String, no length cap (RFC 9651 §3.3.4: parsers must support tokens of at least 512 characters).

```ruby
require "fast/sfv"

Fast::SFV::Token.new("foo")  # => #<Fast::SFV::Token "foo">
Fast::SFV::Token.new("")     # => raises ArgumentError
Fast::SFV::Token.new(:sym)   # => raises TypeError
```

The containers you pass in (the items Array, the params Hash) are emitted from as-is — pass plain mutable ones you built; the wire order of a dictionary and of parameters is the Hash's iteration order.

Construction freezes the instance (shallowly) — the containers and values you pass in stay as you built them; only parse results are deep-frozen end-to-end, because the parser freezes everything it builds.

## Pick the wire type

The Ruby type of a value is its wire-type tag; the content never decides. Serialize dispatches on the Ruby type (RFC 9651 §4.1's algorithms).

The mapping:

| Ruby value | wire |
|---|---|
| `Integer` | integer |
| `Float` | decimal |
| `Fast::SFV::Token` | bare token |
| `String` | quoted sf-string, unless encoding is `ASCII-8BIT` which makes it a byte sequence |
| `true`/`false` | `?1`/`?0` |
| `Fast::SFV::Date` | `@`-date |
| `Fast::SFV::DisplayString` | `%"…"` display string |

The Token arm is matched before the String arm because a Token IS a String — a binary-tagged Token still emits bare.

A `Symbol` is wrong-typed input and raises `SerializeError` (tokens are `Token`s, not Symbols).

```ruby
require "fast/sfv"

Fast::SFV.serialize_item(Fast::SFV::Item.new("foo", {}))  # => "\"foo\""
Fast::SFV.serialize_item(Fast::SFV::Item.new(Fast::SFV::Token.new("foo"), {}))  # => "foo"
Fast::SFV.serialize_item(Fast::SFV::Item.new("hello".b, {}))  # => ":aGVsbG8=:"
```

## Use the short forms

A parameter whose value is `true` is emitted `;key` — no `=`:

```ruby
require "fast/sfv"

item = Fast::SFV::Item.new(5, { "foo" => Fast::SFV::Token.new("bar"), "a" => 1, "b" => false, "c" => true })
Fast::SFV.serialize_item(item)  # => "5;foo=bar;a=1;b=?0;c"
```

A dictionary member whose Item value is `true` is emitted as the bare key with its parameters:

```ruby
require "fast/sfv"

dict = {
  "a" => Fast::SFV::Item.new(false, {}),
  "b" => Fast::SFV::Item.new(true, {}),
  "c" => Fast::SFV::Item.new(true, { "foo" => Fast::SFV::Token.new("bar") })
}
Fast::SFV.serialize_dict(dict)  # => "a=?0, b, c;foo=bar"
```

## Omit an empty container

`serialize_list([])` and `serialize_dict({})` answer `nil` — RFC 9651 §4.1 step 1: an empty container omits the field entirely.

An empty inner list is not an omission:

```ruby
require "fast/sfv"

Fast::SFV.serialize_list([])  # => nil
Fast::SFV.serialize_dict({})  # => nil
Fast::SFV.serialize_list([Fast::SFV::InnerList.new([], {})])  # => "()"
```

An Item is never empty; only the containers answer `nil`.

## Respect the limits

Every violation raises a positioned `Fast::SFV::SerializeError` (see [Diagnose a rejected field value](diagnose-failures.md)).

- **Integer range:** -999,999,999,999,999 .. 999,999,999,999,999 (RFC 9651 §4.1.4 step 1).

```ruby
require "fast/sfv"

Fast::SFV.serialize_item(Fast::SFV::Item.new(999_999_999_999_999, {}))  # => "999999999999999"
Fast::SFV.serialize_item(Fast::SFV::Item.new(1_000_000_000_000_000, {}))  # => raises SerializeError
```

- **Decimal:** must be finite; at most three fraction places, ties rounded to even, as written — `0.5015` → `"0.502"`, `2.0005` → `"2.0"`, `9.9995` → `"10.0"`; at most 12 integer digits after rounding (RFC 9651 §4.1.5).

```ruby
require "fast/sfv"

Fast::SFV.serialize_item(Fast::SFV::Item.new(0.5015, {}))  # => "0.502"
Fast::SFV.serialize_item(Fast::SFV::Item.new(2.0005, {}))  # => "2.0"
Fast::SFV.serialize_item(Fast::SFV::Item.new(9.9995, {}))  # => "10.0"
Fast::SFV.serialize_item(Fast::SFV::Item.new(Float::NAN, {}))  # => raises SerializeError
```

- **String content:** every byte SP or VCHAR (0x20–0x7e); a backslash escapes only `"` and `\` (RFC 9651 §4.1.6).

- **Token and key grammar:** validated on the emit path as a defensive re-check of what the Token constructor already guarantees; keys are lcalpha/`*` then lcalpha/DIGIT/`_`/`-`/`.`/`*` (RFC 9651 §4.1.1.3, §4.1.7).

- **Byte sequence:** RFC 4648 §4 base64 with `=` padding (RFC 9651 §4.1.8).

- **Display string:** value must be Unicode text (UTF-8 or cleanly convertible); `%`, `"` and control/high bytes percent-escape as two lowercase hex digits (RFC 9651 §4.1.11).

- **Wrong shapes:** non-Item to `serialize_item`, non-Array to `serialize_list`, non-Hash to `serialize_dict`, unwrapped members, Symbol keys — all `SerializeError`, never `TypeError`.

```ruby
require "fast/sfv"

Fast::SFV.serialize_item(:foo)  # => raises SerializeError at offset 0
Fast::SFV.serialize_list("1, 2")  # => raises SerializeError
Fast::SFV.serialize_dict({ a: Fast::SFV::Item.new(1, {}) })  # => raises SerializeError
```
