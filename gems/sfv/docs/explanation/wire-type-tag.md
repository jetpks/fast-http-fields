# Why the Ruby type is the wire-type tag

## The problem: one syntax, eight types

`"foo"` (a quoted string) and `foo` (a token) are different wire types whose content can be identical — the content cannot decide the type.

Serialize dispatches on the Ruby type (RFC 9651 §4.1's algorithms); the content never decides.

```ruby
require "fast/sfv"

Fast::SFV.parse_item("\"foo\"").value.class  # => String
Fast::SFV.parse_item("foo").value.class  # => Fast::SFV::Token
```

## The mapping

Parse: each grammar decides — the first byte dispatches into the eight bare-item grammars.

Serialize: the Ruby type dispatches — `Integer`, `Float`, `Token` (before `String`, because a Token IS a String), `String` (sf-string, or byte sequence when tagged `ASCII-8BIT`), `true`/`false`, `Date`, `DisplayString`; anything else fails.

Consequence: `"foo"` the String stays a quoted sf-string, `Fast::SFV::Token.new("foo")` a bare token, and a binary-tagged Token still emits bare.

```ruby
require "fast/sfv"

Fast::SFV.serialize_item(Fast::SFV::Item.new("foo", {}))  # => "\"foo\""
Fast::SFV.serialize_item(Fast::SFV::Item.new(Fast::SFV::Token.new("foo"), {}))  # => "foo"
```

## Why Token is a String subclass, not a Symbol

The 0.1.0 history: token values were Symbols until the switch to `Token < String`.

What String inheritance buys: `==`, `eql?`, `hash` and `to_s` behave exactly as a plain String's — a Token compares equal to the String that spells it in both directions, serves as a Hash key by content, goes wherever a String goes (`send`, JSON).

```ruby
require "fast/sfv"

token = Fast::SFV::Token.new("bar")
token == "bar"  # => true
"bar" == token  # => true
{ "bar" => 1 }[token]  # => 1
"abc".send(Fast::SFV::Token.new("upcase"))  # => "ABC"
```

A Symbol is also a class tag, but it is not a String: it does not compare equal to the String that spells it and does not go where Strings go; `Token` keeps a tag class while inheriting the whole String protocol.

The boundary: `Token.new` validates the whole grammar and freezes — the only Token is a whole, valid, immutable one.

```ruby
require "fast/sfv"

Fast::SFV::Token.new("valid-token")  # => #<Fast::SFV::Token "valid-token">
Fast::SFV::Token.new("a b")  # => raises ArgumentError
Fast::SFV::Token.new("")  # => raises ArgumentError
```

The deliberate divergence: starry, the RFC 8941 reference implementation, returns `Symbol` tokens; fast-sfv documents the divergence rather than following it.

No intern cache: a repeated value builds its own Token — measured +1 object per value worst-case, a per-value constant judged nowhere near a budget demand. See [Performance and allocation budgets](performance.md).

## ASCII-8BIT as the byte-sequence tag

A parsed byte sequence is a frozen `ASCII-8BIT` String — the encoding is the tag; `String#b` / `"...".b` is the idiom for building one.

Encoding is read, not content: `"hello"` is an sf-string, `"hello".b` is `:aGVsbG8=:`.

```ruby
require "fast/sfv"

Fast::SFV.parse_item(":aGVsbG8=:").value.encoding  # => #<Encoding:ASCII-8BIT>
Fast::SFV.serialize_item(Fast::SFV::Item.new("hello", {}))  # => "\"hello\""
Fast::SFV.serialize_item(Fast::SFV::Item.new("hello".b, {}))  # => ":aGVsbG8=:"
```

## What this rules out

No coercion, no content inference, and a `Symbol` raises `SerializeError` — wrong-typed input now that tokens are Tokens.

```ruby
require "fast/sfv"

Fast::SFV.serialize_item(Fast::SFV::Item.new(:foo, {}))  # => raises Fast::SFV::SerializeError
```
