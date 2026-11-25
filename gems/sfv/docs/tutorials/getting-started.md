# Getting started with fast-sfv

fast-sfv parses and emits RFC 9651 Structured Field Values — the
Items, Lists and Dictionaries with parameters that HTTP field
grammars are written against. This tutorial walks one field of each
shape through a parse, back out onto the wire, and through a failure.

## Prerequisites

Ruby 3.4 or later. Install the gem:

```sh
gem install fast-sfv
```

Then require it. The require is `fast/sfv`, not `fast-sfv`:

```ruby
require "fast/sfv"
```

There are no runtime dependencies. The full method surface is in
[Fast::SFV — API reference](../reference/api.md).

## Parse your first Item

An Item is one bare value plus its parameters. `Fast::SFV.parse_item`
takes the field value — a String, or an Array of the field's lines —
and answers a frozen `Fast::SFV::Item`:

```ruby
item = Fast::SFV.parse_item("42;a=1")
item.value  # => 42
item.params # => {"a" => 1}
```

`#value` is one of the eight bare types (here an `Integer`), and
`#params` is the ordered, frozen `Hash` of parameters — empty and
shared when there were none:

```ruby
Fast::SFV.parse_item("42").params # => {}
```

A quoted string value is a frozen UTF-8 `String`; a bare token is a
frozen `Fast::SFV::Token`:

```ruby
Fast::SFV.parse_item("\"foo\"").value # => "foo"
Fast::SFV.parse_item("sugar").value.class # => Fast::SFV::Token
```

Every bare type and its bounds is tabulated in
[Type mapping — RFC 9651 to Ruby](../reference/type-mapping.md).

## Parse a List

A List is members separated by commas — plain Items and inner lists.
`Fast::SFV.parse_list` answers a frozen `Array`, one
`Fast::SFV::Item` or `Fast::SFV::InnerList` per member:

```ruby
list = Fast::SFV.parse_list("sugar, (1 2);a=1, 42")
list.length # => 3
list.map(&:class) # => [Fast::SFV::Item, Fast::SFV::InnerList, Fast::SFV::Item]
list.map(&:to_s) # => ["sugar", "(1 2);a=1", "42"]
```

An inner list carries its member Items in `#items` and its own
parameters in `#params` — the members carry theirs separately:

```ruby
inner = Fast::SFV.parse_list("sugar, (1 2);a=1, 42")[1]
inner.items.map(&:value) # => [1, 2]
inner.params # => {"a" => 1}
```

## Parse a Dictionary

A Dictionary is keyed members. `Fast::SFV.parse_dict` answers a
frozen, ordered `Hash` of `String` keys to `Item`s and `InnerList`s,
so iteration order is the wire order:

```ruby
dict = Fast::SFV.parse_dict("a=1, b=?0")
dict.keys # => ["a", "b"]
dict["a"].value # => 1
dict["b"].value # => false
```

A key without `=` is the Boolean-true short form:

```ruby
Fast::SFV.parse_dict("a, b=1")["a"].value # => true
```

A duplicate key keeps its first position and takes the last value —
the rule RFC 9651 gives dictionaries:

```ruby
dupes = Fast::SFV.parse_dict("a=1, a=2")
dupes.keys # => ["a"]
dupes["a"].value # => 2
```

## Emit back onto the wire

`Fast::SFV.serialize_item`, `serialize_list` and `serialize_dict`
take the same shapes back to the canonical single-line wire form.
A parse round-trips exactly:

```ruby
Fast::SFV.serialize_item(Fast::SFV.parse_item("42;a=1")) # => "42;a=1"
Fast::SFV.serialize_list(Fast::SFV.parse_list("sugar, 42")) # => "sugar, 42"
Fast::SFV.serialize_dict(Fast::SFV.parse_dict("a=1, b=?0")) # => "a=1, b=?0"
```

An empty List or Dictionary serializes to `nil` — RFC 9651 §4.1
step 1: an empty container omits the field entirely, so `nil` is the
signal to not set the field at all:

```ruby
Fast::SFV.serialize_list([]) # => nil
Fast::SFV.serialize_dict({}) # => nil
```

## When a field is not a Structured Field

Parsing is strict: RFC 9651 §1.1 forbids tolerating malformed
content. A malformed field raises `Fast::SFV::ParseError` carrying
`#offset`, the byte position where the parse stopped:

```ruby
Fast::SFV.parse_item("42 42") # raises Fast::SFV::ParseError
```

```ruby
begin
  Fast::SFV.parse_list("1,")
rescue Fast::SFV::ParseError => e
  e.offset # => 2
end
```

The `valid_item?`, `valid_list?` and `valid_dict?` mirrors answer the
same question with a boolean and never raise — false for malformed
content and for a wrong input type alike:

```ruby
Fast::SFV.valid_item?("42") # => true
Fast::SFV.valid_item?("42 42") # => false
Fast::SFV.valid_list?("1,") # => false
Fast::SFV.valid_dict?("a=1") # => true
```

## Where to go next

- [Parse or emit?](../how-to-guides/parse-vs-emit.md) — which entry
  point for which side of the conversation, and what strict means.
- [Handle multi-line fields](../how-to-guides/handle-multi-line-fields.md) —
  the Array entry points and RFC 9651 §4.2's combining rule.
- [Work with byte sequences](../how-to-guides/work-with-byte-sequences.md) —
  the encoding tag and the digest comparison idiom.
- [Fast::SFV — API reference](../reference/api.md) — every module
  function, value object and error.
- [Design decisions in fast-sfv](../explanation/design-decisions.md) —
  why the values look the way they do.
