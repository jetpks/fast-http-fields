# Your first Structured Field Values

You will parse and emit Structured Field Values (RFC 9651) with `Fast::SFV` in about ten minutes.

## What you will learn

- Parse an Item, a List, a Dictionary; read parameters and inner lists; recognize each of the eight bare item types; serialize a value back to the wire; handle a rejected field value.
- Assumes Ruby >= 3.4 and familiarity with HTTP field basics.

## Set up

```sh
gem install fast-sfv
```

```ruby
require "fast/sfv"
```

## Parse an Item

An Item is one bare value plus its parameters (RFC 9651 §3.3).

`Fast::SFV.parse_item(input)` returns a frozen `Fast::SFV::Item`.

`#value` carries the bare item; `#params` the ordered, frozen, String-keyed Hash (empty and shared when there were none).

```ruby
require "fast/sfv"

item = Fast::SFV.parse_item("42; foo=bar")
item.value            # => 42
item.params["foo"]    # => #<Fast::SFV::Token "bar">
item.params["foo"] == "bar"  # => true
```

`foo` is a key; `bar` is a Token, not a String, because its grammar says so — the class is the tag. See [Why the Ruby type is the wire-type tag](../explanation/wire-type-tag.md).

## Parse a List

`Fast::SFV.parse_list(input)` returns a frozen Array of Items and `InnerList`s; empty input parses to the empty list.

An Inner List is a parenthesized group; its members are Items, and the list itself carries parameters (RFC 9651 §3.1.1).

```ruby
require "fast/sfv"

list = Fast::SFV.parse_list("sugar, tea, rum")
list.map(&:value).map(&:to_s)  # => ["sugar", "tea", "rum"]
list.map(&:value).all? { |v| v.is_a?(Fast::SFV::Token) }  # => true

list = Fast::SFV.parse_list("(\"foo\"; a=1;b=2);lvl=5, (\"bar\" \"baz\");lvl=1")
list[0].items[0].value   # => "foo"
list[0].items[0].params == { "a" => 1, "b" => 2 }  # => true
list[0].params == { "lvl" => 5 }                    # => true
```

Note: `"foo"` in the wire parsed to a plain String (`"foo"`). `sugar` parsed to a `Fast::SFV::Token`.

## Parse a Dictionary

`Fast::SFV.parse_dict(input)` returns a frozen, ordered Hash of String keys to Items and `InnerList`s; empty input parses to the empty dictionary.

A member without `=` is Boolean `true` with parameters — the short form (RFC 9651 §4.2.2 step 2.3).

Insertion order is the wire order and survives as Ruby Hash order — RFC 9651 §3.2: Dictionaries are ordered maps, accessed by index and by key.

```ruby
require "fast/sfv"

dict = Fast::SFV.parse_dict("a=1, b;foo=bar, c=(1 2)")
dict.keys               # => ["a", "b", "c"]
dict["b"].value         # => true
dict["b"].params["foo"] == "bar"  # => true
dict["c"].items.map(&:value)  # => [1, 2]
```

## The eight bare item types

| wire | Ruby value | type |
|---|---|---|
| `42` / `-1.23` | `Integer` / `Float` | integer / decimal (RFC 9651 §3.3.1–§3.3.2) |
| `"foo"` | frozen UTF-8 `String` | string (RFC 9651 §3.3.3) |
| `sugar` | `Fast::SFV::Token` | token (RFC 9651 §3.3.4) |
| `:aGVsbG8=:` | frozen ASCII-8BIT `String` | byte sequence (RFC 9651 §3.3.5) |
| `?1` / `?0` | `true` / `false` | boolean (RFC 9651 §3.3.6) |
| `@1659578233` | `Fast::SFV::Date` (`#value` → `1659578233`) | date (RFC 9651 §3.3.7) |
| `%"f%c3%bc"` | `Fast::SFV::DisplayString` (`#value` → `"fü"`) | display string (RFC 9651 §3.3.8) |

```ruby
require "fast/sfv"

Fast::SFV.parse_item(":aGVsbG8=:").value  # => "hello"
Fast::SFV.parse_item(":aGVsbG8=:").value.encoding  # => #<Encoding:ASCII-8BIT>
Fast::SFV.parse_item("@1659578233").value.value  # => 1659578233
Fast::SFV.parse_item("%\"f%c3%bc\"").value.value  # => "fü"
```

See [API reference](../reference/api.md) for the full mapping.

## Emit it back

`Fast::SFV.serialize_list(list)` / `serialize_dict(dict)` / `serialize_item(item)` produce the canonical wire form as a fresh, mutable US-ASCII String.

The empty List or Dictionary serializes to `nil` — an omitted field, not an empty string (RFC 9651 §4.1 step 1).

Building a value by hand: `Item.new(value, params)` and `InnerList.new(items, params)` freeze at construction.

```ruby
require "fast/sfv"

list = [
  Fast::SFV::Item.new(1, {}),
  Fast::SFV::InnerList.new([Fast::SFV::Item.new(2, {})], { "a" => 1 })
]
Fast::SFV.serialize_list(list)  # => "1, (2);a=1"
Fast::SFV.serialize_list([])    # => nil
```

## When the field is wrong

Malformed content raises `Fast::SFV::ParseError`; `#offset` is the byte position in the combined input where the parse stopped.

```ruby
require "fast/sfv"

begin
  Fast::SFV.parse_item("foo bar")
rescue Fast::SFV::ParseError => e
  e.message  # => "unexpected content after the value at offset 4"
  e.offset   # => 4
end
```

When you only need a yes/no:

```ruby
require "fast/sfv"

Fast::SFV.valid_list?("1,")  # => false
```

Everything reachable from a parse result is frozen — `FrozenError` on mutation attempts:

```ruby
require "fast/sfv"

item = Fast::SFV.parse_item("42; foo=bar")
item.params["foo"] = "baz"  # => raises FrozenError
```

## Where next

- [Parse a field value](../how-to-guides/parse-field-values.md) — entry points, field lines, walking results
- [Serialize a field value](../how-to-guides/serialize-field-values.md) — emit, build by hand, wire types, limits
- [Validate a field value without exceptions](../how-to-guides/validate-field-values.md) — boolean predicates
- [Diagnose a rejected field value](../how-to-guides/diagnose-failures.md) — offsets and rescue strategy
- [API reference](../reference/api.md) — full signatures and type map
- [Conformance and the httpwg corpus](../reference/conformance.md) — RFC coverage and corpus counts
