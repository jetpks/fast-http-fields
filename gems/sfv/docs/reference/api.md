# Fast::SFV — API reference

`require "fast/sfv"` — the require path is `fast/sfv`, not
`fast-sfv`. Requires Ruby `>= 3.4`, with zero runtime dependencies.
`Fast::SFV` is a module; its module functions are the whole surface,
and every value it answers is deep-frozen. `Fast::SFV::VERSION` is
`"0.1.0"`.

## Input contract

Every parse entry point takes the field value one of two ways:

- a String — one field value, as the transport combined it;
- an Array of String field lines — the field's lines, which
  fast-sfv joins with `", "` per RFC 9651 §4.2's combining rule (a
  Rack join conforms).

Anything else raises plain `TypeError` — a wrong type is a caller
bug, not field content:

```ruby
Fast::SFV.parse_item(42) # raises TypeError
Fast::SFV.parse_list([42]) # raises TypeError
```

Every serialize entry point takes the Ruby value shapes documented
under each function below, and answers a fresh US-ASCII `String` the
caller owns — or `nil` for an empty List or Dictionary.

## Parsing

Strict: RFC 9651 §1.1 forbids tolerating malformed field content, so
a value that is not a Structured Field Value of the asked shape
raises `Fast::SFV::ParseError` carrying `#offset`. Results are frozen
(see [Type mapping — RFC 9651 to Ruby](type-mapping.md)).

### `.parse_item`

```text
Fast::SFV.parse_item(input) -> Fast::SFV::Item
```

One RFC 9651 Item — a bare item plus its parameters — as a frozen
`Fast::SFV::Item`.

```ruby
item = Fast::SFV.parse_item("42;a=1")
item.value # => 42
item.params # => {"a" => 1}
```

### `.parse_list`

```text
Fast::SFV.parse_list(input) -> frozen Array of Fast::SFV::Item and Fast::SFV::InnerList
```

One RFC 9651 List as a frozen `Array`. Empty input is the empty
list.

```ruby
list = Fast::SFV.parse_list("sugar, (1 2)")
list.length # => 2
list.map(&:class) # => [Fast::SFV::Item, Fast::SFV::InnerList]
```

### `.parse_dict`

```text
Fast::SFV.parse_dict(input) -> frozen, ordered Hash of String keys to Items and InnerLists
```

One RFC 9651 Dictionary as a frozen, ordered `Hash` — iteration
order is the wire order, a duplicate key keeps its first position and
takes its last value, and a key without `=` is the Boolean-true short
form.

```ruby
dict = Fast::SFV.parse_dict("a=1, a=2, i")
dict.keys # => ["a", "i"]
dict["a"].value # => 2
dict["i"].value # => true
```

## Validity predicates

The same strict parses with a boolean answer that never raises —
`false` for malformed content and for a wrong input type alike. Use
them at trust boundaries; use the parses where failure is a bug.

### `.valid_item?`

```text
Fast::SFV.valid_item?(input) -> true or false
```

```ruby
Fast::SFV.valid_item?("42") # => true
Fast::SFV.valid_item?("42 42") # => false
```

### `.valid_list?`

```text
Fast::SFV.valid_list?(input) -> true or false
```

```ruby
Fast::SFV.valid_list?("1, 42") # => true
Fast::SFV.valid_list?("1,") # => false
```

### `.valid_dict?`

```text
Fast::SFV.valid_dict?(input) -> true or false
```

```ruby
Fast::SFV.valid_dict?("a=1") # => true
Fast::SFV.valid_dict?("A=1") # => false
```

## Serializing

Strict: a sender never puts a value on the wire that is not a
Structured Field Value — anything non-serializable raises
`Fast::SFV::SerializeError` carrying `#offset`, the byte offset into
the output built so far. There is no coercion: the Ruby type of a
value is its wire-type tag.

### `.serialize_item`

```text
Fast::SFV.serialize_item(item) -> String (US-ASCII), the canonical RFC 9651 §4.1.3 form
```

One `Fast::SFV::Item` — the bare item, then its parameters. Exactly
what `Item#to_s` answers.

```ruby
Fast::SFV.serialize_item(Fast::SFV::Item.new("foo", {})) # => "\"foo\""
Fast::SFV.serialize_item(Fast::SFV::Item.new(Fast::SFV::Token.new("foo"), {})) # => "foo"
```

### `.serialize_list`

```text
Fast::SFV.serialize_list(list) -> String, or nil for the empty List
```

An `Array` of Items and InnerLists — the canonical §4.1.1 form, or
`nil` for the empty List (RFC 9651 §4.1 step 1: an empty container
omits the field entirely).

```ruby
Fast::SFV.serialize_list([Fast::SFV::Item.new(1, {}), Fast::SFV::InnerList.new([Fast::SFV::Item.new(2, {})], {})]) # => "1, (2)"
Fast::SFV.serialize_list([]) # => nil
```

### `.serialize_dict`

```text
Fast::SFV.serialize_dict(dict) -> String, or nil for the empty Dictionary
```

An ordered `Hash` of `String` keys to Items and InnerLists — the
canonical §4.1.2 form, in the Hash's iteration order, with a member
whose Item value is Boolean true using the valueless short form.

```ruby
Fast::SFV.serialize_dict("a" => Fast::SFV::Item.new(1, {}), "b" => Fast::SFV::Item.new(true, {})) # => "a=1, b"
Fast::SFV.serialize_dict({}) # => nil
```

## Value objects

All five are frozen at construction, and none of them defines value
equality — they compare by identity, so compare `#value`s (a
`Fast::SFV::Token` is the exception: as a `String` subclass it
compares by content).

### `Fast::SFV::Item`

One bare item plus its parameters. `#value` is one of the eight bare
types; `#params` is the ordered, frozen, String-keyed `Hash` the
parser filled (empty and shared when there were none). `#to_s` is the
canonical wire form, exactly `serialize_item`'s answer:

```ruby
item = Fast::SFV::Item.new(1, { "a" => 2 })
item.to_s # => "1;a=2"
item.frozen? # => true
```

The instance is frozen at construction; the parameter `Hash` you hand
it is yours — a parse result's parameters are frozen, a hand-built
Item's are the `Hash` you passed:

```ruby
Fast::SFV.parse_item("1;a=2").params.frozen? # => true
Fast::SFV::Item.new(1, { "a" => 2 }).params.frozen? # => false
```

### `Fast::SFV::InnerList`

A frozen `Array` of Items in `#items`, plus the parameters that
belong to the list itself in `#params` — the member Items carry
their own. `#to_s` is the canonical wire form, `"()"` for the empty
list (only the top-level containers omit a field):

```ruby
inner = Fast::SFV::InnerList.new([Fast::SFV::Item.new(1, {})], { "a" => 1 })
inner.to_s # => "(1);a=1"
Fast::SFV::InnerList.new([], {}).to_s # => "()"
```

### `Fast::SFV::Date`

The RFC 9651 Date type: `#value` is the `Integer` delta-seconds from
1970-01-01T00:00:00Z. `Integer` cannot be subclassed, so the wrapper
carries the type tag the wire round-trip needs. `#to_s` is the
canonical wire form:

```ruby
date = Fast::SFV::Date.new(1659578233)
date.value # => 1659578233
date.to_s # => "@1659578233"
```

### `Fast::SFV::DisplayString`

The RFC 9651 Display String type: `#value` is a frozen UTF-8
`String` that may carry non-ASCII content. `#to_s` is the canonical
wire form — `%"` … `"`, with `%`, DQUOTE and the control and high
bytes percent-encoded as two lowercase hex digits:

```ruby
display = Fast::SFV::DisplayString.new("fü")
display.value # => "fü"
display.to_s # => "%\"f%c3%bc\""
```

### `Fast::SFV::Token`

The RFC 9651 Token type: a frozen `String` subclass whose class is
the wire-type tag. The content keeps plain String semantics — `==`,
`eql?`, `hash` and `to_s` behave exactly as a plain String's — while
Token-ness is what the parse and emit paths dispatch on.
`Fast::SFV::Token.new` validates the whole token grammar
(RFC 9651 §3.3.4: ALPHA or `*` first, then tchar, `:` and `/`) and
raises `ArgumentError` for invalid content, `TypeError` for a
non-String. `#inspect` names the class so debugging shows it:

```ruby
token = Fast::SFV::Token.new("bar")
token == "bar" # => true
"bar" == token # => true
token.to_s # => "bar"
token.inspect # => "#<Fast::SFV::Token \"bar\">"
{ token => 1 }["bar"] # => 1
```

```ruby
Fast::SFV::Token.new("1foo") # raises ArgumentError
Fast::SFV::Token.new(1) # raises TypeError
```

## Errors

`Fast::SFV::Error` is the family root — rescue it to guard the whole
surface. Both subclasses carry `#offset` (an `Integer`) and
`#message`.

### `Fast::SFV::ParseError`

The field value is not a Structured Field Value of the asked shape.
`#offset` is the byte position in the combined input where the parse
stopped:

```ruby
begin
  Fast::SFV.parse_item("42 42")
rescue Fast::SFV::ParseError => e
  e.offset # => 3
end
```

### `Fast::SFV::SerializeError`

The value tree is not serializable. `#offset` is the byte position in
the output built so far — the emit path never raises `TypeError`,
because on emit the wrongness is in the value tree being sent:

```ruby
begin
  Fast::SFV.serialize_item(Fast::SFV::Item.new(1, { "a" => nil }))
rescue Fast::SFV::SerializeError => e
  e.offset # => 4
end
```

```ruby
Fast::SFV.serialize_item("no") # raises Fast::SFV::SerializeError
```

## Frozen results

Everything a parse answers is deep-frozen: the `Item`s and
`InnerList`s, the list `Array`, the ordered dictionary and parameter
`Hashes` with their `String` keys, and every `String` the parse
produced. A serialized answer is a fresh `String` the caller owns.
Nothing reachable from a parse result can be mutated, so results are
safe to share across threads without copying:

```ruby
result = Fast::SFV.parse_dict("a=1")
result.frozen? # => true
result["a"].frozen? # => true
result["a"].value.frozen? # => true
```

## Where to go next

- [Type mapping — RFC 9651 to Ruby](type-mapping.md) — the nine wire
  types against the Ruby values that carry them.
- [Parse or emit?](../how-to-guides/parse-vs-emit.md) — which entry
  point for which side.
- [Design decisions in fast-sfv](../explanation/design-decisions.md) —
  why these shapes and not others.
