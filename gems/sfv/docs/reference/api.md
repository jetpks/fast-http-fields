# API reference

The complete public surface. No prose essays — see the [explanation](../explanation/strictness.md) and how-to guides for rationale and recipes.

## The module

`Fast::SFV`, required as `require "fast/sfv"`; `Fast::SFV::VERSION` is `"0.1.0"`.

Ruby >= 3.4, RubyGems >= 3.5.3, zero runtime dependencies.

Only the module functions are public: `Parser` and `Serializer` are `private_constant`s.

## Parsing

- `Fast::SFV.parse_item(input) → Fast::SFV::Item` — RFC 9651 §4.2 with field_type "item"; arity 1.
- `Fast::SFV.parse_list(input) → frozen Array[Item|InnerList]` — arity 1; empty input → `[]`.
- `Fast::SFV.parse_dict(input) → frozen, ordered Hash[String → Item|InnerList]` — arity 1; empty input → `{}`.

Raises: `Fast::SFV::ParseError` for malformed content; `TypeError` for a non-String/non-Array input or a non-String line.

Input: one String field value, or the field's lines as an Array of Strings combined with `", "`; the whole value must be ASCII.

```ruby
require "fast/sfv"

Fast::SFV.parse_item("42").value  # => 42
Fast::SFV.parse_list("1, 2").map(&:value)  # => [1, 2]
Fast::SFV.parse_dict("a=1").keys  # => ["a"]
```

## Validity predicates

- `Fast::SFV.valid_item?(input) → true/false` — arity 1; never raises; `false` for malformed content and wrong input types alike.
- `Fast::SFV.valid_list?(input) → true/false` — same.
- `Fast::SFV.valid_dict?(input) → true/false` — same.

```ruby
require "fast/sfv"

Fast::SFV.valid_item?("42")  # => true
Fast::SFV.valid_item?("foo bar")  # => false
Fast::SFV.valid_item?(42)  # => false
```

## Serializing

- `Fast::SFV.serialize_item(item) → String` — the canonical RFC 9651 §4.1.3 form; arity 1; an Item is required.
- `Fast::SFV.serialize_list(list) → String | nil` — RFC 9651 §4.1.1; arity 1; an Array of Items and InnerLists is required; `nil` for the empty List.
- `Fast::SFV.serialize_dict(dict) → String | nil` — RFC 9651 §4.1.2; arity 1; an ordered Hash of String keys to Items and InnerLists is required; `nil` for the empty Dictionary.

Every output is a fresh, mutable US-ASCII String the caller owns; the Ruby type of a value is its wire-type tag.

Raises: `Fast::SFV::SerializeError` (positioned; never `TypeError`) for any non-serializable input.

```ruby
require "fast/sfv"

item = Fast::SFV::Item.new(42, {})
Fast::SFV.serialize_item(item)  # => "42"
Fast::SFV.serialize_list([])  # => nil
```

## Value classes

### Fast::SFV::Item

`attr_reader :value, :params`; `Item.new(value, params)`; frozen at construction; `#to_s` is the canonical RFC 9651 §4.1.3 wire form, identical to `serialize_item`'s answer.

```ruby
require "fast/sfv"

item = Fast::SFV::Item.new(42, { "a" => 1 })
item.value  # => 42
item.params  # => {"a"=>1}
item.to_s  # => "42;a=1"
```

### Fast::SFV::InnerList

`attr_reader :items, :params`; `InnerList.new(items, params)`; frozen; `#to_s` is RFC 9651 §4.1.1.1: `"("`, items joined by single SPs, `")"`, then the list's own parameters; `"()"` for the empty list.

```ruby
require "fast/sfv"

inner = Fast::SFV::InnerList.new([Fast::SFV::Item.new(1, {}), Fast::SFV::Item.new(2, {})], { "a" => 1 })
inner.items.map(&:value)  # => [1, 2]
inner.params  # => {"a"=>1}
inner.to_s  # => "(1 2);a=1"
```

### Fast::SFV::Token

`Token < String`; `Token.new(content)`; validates the full token grammar (ALPHA or `*` first, then tchar/`:`/`/`) and freezes: `ArgumentError` for invalid content, `TypeError` for a non-String, no length cap (RFC 9651 §3.3.4: parsers must support tokens of at least 512 characters).

String semantics inherited untouched — `==`, `eql?`, `hash`, `to_s` behave exactly as a plain String's, so a Token compares equal to the String that spells it in both directions and serves as a Hash key by content; `#inspect` is overridden to `#<Fast::SFV::Token "bar">`.

```ruby
require "fast/sfv"

token = Fast::SFV::Token.new("bar")
token == "bar"  # => true
"bar" == token  # => true
{ "bar" => 1 }[token]  # => 1
token.inspect  # => "#<Fast::SFV::Token \"bar\">"
```

### Fast::SFV::Date

`attr_reader :value` (Integer delta-seconds from 1970-01-01T00:00:00Z; Integer cannot be subclassed, so the wrapper is the type tag); `Date.new(value)`; frozen; `#to_s` is RFC 9651 §4.1.10: `"@" + integer`.

```ruby
require "fast/sfv"

date = Fast::SFV::Date.new(1_659_578_233)
date.value  # => 1659578233
date.to_s  # => "@1659578233"
```

### Fast::SFV::DisplayString

`attr_reader :value` (the percent-decoded UTF-8 String); `DisplayString.new(value)`; frozen; `#to_s` is RFC 9651 §4.1.11.

```ruby
require "fast/sfv"

ds = Fast::SFV::DisplayString.new("fü")
ds.value  # => "fü"
ds.to_s  # => "%\"f%c3%bc\""
```

## Errors

### Fast::SFV::Error

`< StandardError`; the family root.

### Fast::SFV::ParseError

`< Error`; `ParseError.new(message, offset)`; `attr_reader :offset` — Integer byte position in the combined input, `0..input.bytesize`; message carries the reason. Format: `"<reason> at offset <n>"`.

### Fast::SFV::SerializeError

`< Error`; `SerializeError.new(message, offset)`; `attr_reader :offset` — Integer byte position in the output built so far, `0..output.bytesize`; `0` for a wrong top-level shape.

## The bare item type map

| bare type | wire example | parse produces | serialize accepts |
|---|---|---|---|
| integer | `42` | `Integer` | `Integer` (±999,999,999,999,999) |
| decimal | `-1.23` | `Float` | `Float` (finite) |
| string | `"foo"` | frozen UTF-8 `String` | any non-ASCII-8BIT `String` |
| token | `sugar` | `Fast::SFV::Token` | `Fast::SFV::Token` |
| byte sequence | `:aGVsbG8=:` | frozen ASCII-8BIT `String` | `String` tagged `Encoding::ASCII_8BIT` |
| boolean | `?1` / `?0` | `true` / `false` | `true` / `false` |
| date | `@1659578233` | `Fast::SFV::Date` | `Fast::SFV::Date` |
| display string | `%"f%c3%bc"` | `Fast::SFV::DisplayString` | `Fast::SFV::DisplayString` |

A `Symbol` is wrong-typed input on the emit path and raises; nothing is coerced and no type is inferred from content.

## Immutability and ownership

- Parse results are deep-frozen (containers, Items, InnerLists, Hashes, every produced String).
- Items and inner lists without parameters share one frozen empty Hash.
- Serialize outputs are fresh, mutable, US-ASCII, and owned by the caller.
- Hand-built value objects freeze the instance at construction (shallowly — what you pass in stays yours); hand-built `Token`s are always whole, valid, and immutable.

## Requirements

- Ruby >= 3.4 (CI matrix covers 3.4 and 4.0); RubyGems >= 3.5.3; no runtime dependencies.

See [Conformance and the httpwg corpus](conformance.md) for the RFC coverage map.
