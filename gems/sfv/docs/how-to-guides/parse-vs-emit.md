# Parse or emit?

Which entry point you call depends on which side of the conversation
you are on: a recipient parses, a sender serializes. Both directions
are strict — RFC 9651 §1.1 forbids tolerating malformed content on
the way in, and a sender never puts a value on the wire that is not a
Structured Field Value.

## Receiving: parse

Parse the field value you were handed — a String, or an Array of the
field's lines (see
[Handle multi-line fields](handle-multi-line-fields.md)):

```ruby
Fast::SFV.parse_item("42;a=1").value # => 42
Fast::SFV.parse_list("sugar, 42").map(&:value) # => ["sugar", 42]
Fast::SFV.parse_dict("a=1").keys # => ["a"]
```

Malformed content raises a positioned `Fast::SFV::ParseError`; a
non-String, non-Array input raises plain `TypeError` (a wrong type is
a caller bug, not field content):

```ruby
Fast::SFV.parse_item(42) # raises TypeError
Fast::SFV.parse_item("42 42") # raises Fast::SFV::ParseError
```

## Sending: serialize

Build the value and serialize it. The Ruby type of every value IS its
wire-type tag — an `Integer` is an integer, a `Float` a decimal, a
`Fast::SFV::Token` a token, a `String` a quoted string unless it is
tagged ASCII-8BIT and so a byte sequence. The content never decides:

```ruby
Fast::SFV.serialize_item(Fast::SFV::Item.new("foo", {})) # => "\"foo\""
Fast::SFV.serialize_item(Fast::SFV::Item.new(Fast::SFV::Token.new("foo"), {})) # => "foo"
Fast::SFV.serialize_item(Fast::SFV::Item.new("foo".b, {})) # => ":Zm9v:"
```

The emit is always strict: anything not serializable raises
`Fast::SFV::SerializeError` with the byte offset into the output built
so far. There is no coercion. Since tokens became `Fast::SFV::Token`
values, a `Symbol` is wrong-typed input and raises — the type is the
tag, and a `Symbol` is not a token:

```ruby
Fast::SFV.serialize_item(Fast::SFV::Item.new(:sugar, {})) # raises Fast::SFV::SerializeError
```

An empty List or Dictionary answers `nil` — the field is omitted
entirely:

```ruby
Fast::SFV.serialize_list([]) # => nil
```

## When you only want a boolean

The `valid_item?`, `valid_list?` and `valid_dict?` mirrors are the
strict parse with a boolean answer that never raises — useful at a
trust boundary where the field is foreign input:

```ruby
Fast::SFV.valid_item?("42") # => true
Fast::SFV.valid_item?("1.2.3") # => false
Fast::SFV.valid_list?("1, 2") # => true
Fast::SFV.valid_dict?("A=1") # => false
```

## Hand-building values

The parse is not the only way to get a serializable value — build one
by hand. An `Item` wraps a bare value and its parameters; an
`InnerList` wraps the member Items and the list's own parameters:

```ruby
item = Fast::SFV::Item.new(5, { "foo" => Fast::SFV::Token.new("bar") })
item.to_s # => "5;foo=bar"
inner = Fast::SFV::InnerList.new([Fast::SFV::Item.new(1, {}), Fast::SFV::Item.new(2, {})], {})
inner.to_s # => "(1 2)"
Fast::SFV.serialize_list([item, inner]) # => "5;foo=bar, (1 2)"
```

`Fast::SFV::Token` is a `String` subclass, and its constructor
validates the whole token grammar at the boundary — RFC 9651 §3.3.4:
ALPHA or `*` first, then tchar, `:` and `/`. Invalid content raises
`ArgumentError`; a non-String raises `TypeError`:

```ruby
Fast::SFV::Token.new("foo123/456") # => "foo123/456"
Fast::SFV::Token.new("1foo") # raises ArgumentError
Fast::SFV::Token.new("") # raises ArgumentError
Fast::SFV::Token.new(1) # raises TypeError
```

A hand-built value is checked by the same strict emit — a `nil`
parameter value, an out-of-range integer, an invalid key, all raise
`SerializeError` with the offset into the output:

```ruby
Fast::SFV.serialize_item(Fast::SFV::Item.new(1, { "a" => nil })) # raises Fast::SFV::SerializeError
```

## Where to go next

- [Fast::SFV — API reference](../reference/api.md) — the signatures
  and one example for every entry point.
- [Type mapping — RFC 9651 to Ruby](../reference/type-mapping.md) —
  the nine wire types against the Ruby values that carry them.
- [Design decisions in fast-sfv](../explanation/design-decisions.md) —
  why the type is the tag, and what that rules out.
- [Getting started with fast-sfv](../tutorials/getting-started.md) —
  the walkthrough this guide assumes.
