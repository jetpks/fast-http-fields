# Type mapping — RFC 9651 to Ruby

RFC 9651 defines nine shapes that appear in a Structured Field Value;
this is the mapping fast-sfv answers for each, and the dispatch the
emit path reads to take each back to the wire. The rule underneath
both directions: the Ruby type or tag IS the wire-type tag — the
content never decides.

| RFC 9651 type | Ruby value | Notes |
|---|---|---|
| Integer | `Integer` | ±999,999,999,999,999; 15 digits |
| Decimal | `Float` | exact: every SFV decimal < 2^53; no `BigDecimal` |
| String | frozen UTF-8 `String` | ASCII-only content |
| Token | frozen `Fast::SFV::Token < String` | the class is the wire-type tag |
| Byte Sequence | frozen ASCII-8BIT `String` | the encoding is the wire-type tag |
| Boolean | `true` / `false` | |
| Date | `Fast::SFV::Date` | minimal wrapper; `#value` is the Integer delta-seconds |
| Display String | `Fast::SFV::DisplayString` | minimal wrapper; percent-encoded, UTF-8, lowercase hex |
| Parameters / Dictionaries | frozen ordered `Hash` | duplicate keys: last value wins, first position kept |

## The eight bare item types on the parse side

```ruby
Fast::SFV.parse_item("42").value # => 42
Fast::SFV.parse_item("-1.23").value # => -1.23
Fast::SFV.parse_item("\"foo\"").value # => "foo"
Fast::SFV.parse_item("sugar").value # => "sugar"
Fast::SFV.parse_item(":aGVsbG8=:").value # => "hello"
Fast::SFV.parse_item("?1").value # => true
Fast::SFV.parse_item("?0").value # => false
Fast::SFV.parse_item("@1659578233").value.value # => 1659578233
Fast::SFV.parse_item("%\"f%c3%bc\"").value.value # => "fü"
```

The classes and tags behind those values:

```ruby
Fast::SFV.parse_item("-1.23").value.class # => Float
Fast::SFV.parse_item("sugar").value.class # => Fast::SFV::Token
Fast::SFV.parse_item("@1659578233").value.class # => Fast::SFV::Date
Fast::SFV.parse_item("%\"f%c3%bc\"").value.class # => Fast::SFV::DisplayString
Fast::SFV.parse_item("\"foo\"").value.encoding # => Encoding::UTF_8
Fast::SFV.parse_item(":aGVsbG8=:").value.encoding # => Encoding::ASCII_8BIT
```

Every one of those values is frozen, as is every container they
arrive in.

## Integer bounds

The 15-digit range is both directions — a 15-digit value parses, a
16-digit value fails the parse, and the strict emit refuses anything
past the bound rather than truncate it:

```ruby
Fast::SFV.parse_item("999999999999999").value # => 999999999999999
Fast::SFV.parse_item("9999999999999999") # raises Fast::SFV::ParseError
Fast::SFV.serialize_item(Fast::SFV::Item.new(999999999999999, {})) # => "999999999999999"
```

## Decimal is Float, exactly

An SFV decimal is at most 12 integer digits and 3 fraction digits, so
every value fits a binary double with room to spare — every SFV
decimal is smaller than 2^53. `Float` is exact for the whole range,
which is why there is no `BigDecimal` in the mapping: no precision is
lost that a wider type could recover. The emit writes the decimal's
digits as `Float#to_s` spells them, rounded to three fraction places
with ties to even.

```ruby
Fast::SFV.parse_item("-1.23").value # => -1.23
Fast::SFV.serialize_item(Fast::SFV::Item.new(1.23, {})) # => "1.23"
```

## Token: the class is the tag

A quoted string parses to a plain frozen UTF-8 `String`; a bare token
parses to a frozen `Fast::SFV::Token`. `Token` is a `String`
subclass, so the content keeps full String semantics — it compares
equal to the String that spells it, in both directions, and serves as
a `Hash` key by content — while Token-ness is what the parse and emit
paths dispatch on:

```ruby
Fast::SFV.parse_item("sugar").value == "sugar" # => true
"sugar" == Fast::SFV.parse_item("sugar").value # => true
{ Fast::SFV::parse_item("sugar").value => 1 }["sugar"] # => 1
```

Construction is the boundary: `Fast::SFV::Token.new` validates the
whole token grammar — RFC 9651 §3.3.4, ALPHA or `*` as the first
byte, then tchar, `:` and `/` — and raises `ArgumentError` otherwise:

```ruby
Fast::SFV::Token.new("*foo") == "*foo" # => true
Fast::SFV::Token.new("1foo") # raises ArgumentError
```

A `Symbol` is wrong-typed input for the emit, not a token — see
[Parse or emit?](../how-to-guides/parse-vs-emit.md).

## Byte Sequence: the encoding is the tag

A byte sequence parses to a `String` tagged `Encoding::ASCII_8BIT`; a
string value parses to a `String` tagged UTF-8. The encoding — not
the content — is what says bytes versus text, and it is what makes
the digest idiom work bytewise:

```ruby
require "digest"

body = "the request body"
parsed = Fast::SFV.parse_item(":#{[Digest::SHA256.digest(body)].pack("m0")}:")
parsed.value == Digest::SHA256.digest(body) # => true
```

The working detail is in
[Work with byte sequences](../how-to-guides/work-with-byte-sequences.md).

## Date and Display String: the minimal wrappers

`Integer` cannot be subclassed, so the two RFC 9651 types whose wire
form needs a distinguishing mark are carried by minimal frozen
wrappers instead — `Fast::SFV::Date` with the `Integer`
delta-seconds in `#value`, `Fast::SFV::DisplayString` with the
percent-decoded UTF-8 `String` in `#value`. Plain `Integer` and
plain `String` keep their unmarked wire forms, so a wrapper is only
built where the round-trip demands the tag:

```ruby
Fast::SFV.serialize_item(Fast::SFV::Item.new(1659578233, {})) # => "1659578233"
Fast::SFV.serialize_item(Fast::SFV::Item.new(Fast::SFV::Date.new(1659578233), {})) # => "@1659578233"
Fast::SFV.serialize_item(Fast::SFV::Item.new("fü", {})) # raises Fast::SFV::SerializeError
Fast::SFV.serialize_item(Fast::SFV::Item.new(Fast::SFV::DisplayString.new("fü"), {})) # => "%\"f%c3%bc\""
```

## Parameters and Dictionaries: the frozen ordered Hash

Parameters and Dictionaries both arrive as frozen, ordered `Hashes`
with `String` keys, so iteration order is the wire order and
index-and-key access is `each_with_index`-style. Ruby's `Hash`
assignment implements RFC 9651's duplicate-key rule exactly — the
last value wins and the first position is kept — on both containers:

```ruby
dict = Fast::SFV.parse_dict("a=1, a=2")
dict["a"].value # => 2
dict.keys # => ["a"]
Fast::SFV.parse_item("5;foo=1;foo=2").params # => {"foo" => 2}
```

A valueless dictionary member or parameter is Boolean true:

```ruby
Fast::SFV.parse_dict("a, b=1")["a"].value # => true
Fast::SFV.parse_item("5;foo").params # => {"foo" => true}
```

## The emit dispatch

Emit accepts the same shapes and dispatches on the same tags: a
plain `String` emits quoted, a `Fast::SFV::Token` emits bare, a
binary-tagged `String` emits `:base64:`. The Token arm is read
before the String arm — a `Token` IS a `String` — so a binary-tagged
`Token` still emits bare:

```ruby
Fast::SFV.serialize_item(Fast::SFV::Item.new("foo", {})) # => "\"foo\""
Fast::SFV.serialize_item(Fast::SFV::Item.new(Fast::SFV::Token.new("foo"), {})) # => "foo"
Fast::SFV.serialize_item(Fast::SFV::Item.new("foo".b, {})) # => ":Zm9v:"
Fast::SFV.serialize_item(Fast::SFV::Item.new(Fast::SFV::Token.new("foo".b), {})) # => "foo"
```

Anything else raises `Fast::SFV::SerializeError` — there is no
coercion and no content inference.

## Where to go next

- [Fast::SFV — API reference](api.md) — the entry points that answer
  and consume these values.
- [Work with byte sequences](../how-to-guides/work-with-byte-sequences.md) —
  the encoding tag in practice.
- [Design decisions in fast-sfv](../explanation/design-decisions.md) —
  why this mapping and not the alternatives.
