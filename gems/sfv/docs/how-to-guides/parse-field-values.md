# Parse a field value

Task-oriented recipe. Assumes familiarity with Structured Field Values; for the guided introduction see [Your first Structured Field Values](../tutorials/structured-fields.md). No serializer content here — see [Serialize a field value](serialize-field-values.md).

## Choose the entry point

The field's definition says which of the three shapes it is (RFC 9651 §2, §2.1).

```ruby
require "fast/sfv"

Fast::SFV.parse_item(input)  # => Fast::SFV::Item
Fast::SFV.parse_list(input)  # => frozen Array of Item / InnerList
Fast::SFV.parse_dict(input)  # => frozen, ordered Hash, String keys
```

All three are module functions on `Fast::SFV`; the `Parser` class itself is a `private_constant`.

## Pass the field's lines

A String input is one field value, used as given; an Array input is the field's lines, combined with `", "` before parsing (RFC 9651 §4.2 field-line combining; a Rack-style array of lines conforms).

Each Array member must be a String (a String subclass included); anything else raises `TypeError` with message `an Array of String field lines is required (got <Class>)`.

An input that is neither String nor Array raises `TypeError` with message `a String or an Array of String field lines is required (got <Class>)` — a caller bug, not field content.

The whole field value must be ASCII; a byte above 0x7F fails the parse before any grammar runs (RFC 9651 §4.2 step 1).

```ruby
require "fast/sfv"

Fast::SFV.parse_list(%w[1 42]).map(&:value)      # => [1, 42]
Fast::SFV.parse_list(["\"foo", "bar\""]).map(&:value)  # => ["foo, bar"]
```

Note: a string split across lines gains the inserted comma (RFC 9651 §4.2 caveat). `["\"foo", "bar\""]` joins to `"\"foo, bar\""` and parses as a single string value `"foo, bar"`.

## Parse the empty field

```ruby
require "fast/sfv"

Fast::SFV.parse_list("")   # => []
Fast::SFV.parse_list([])   # => []
Fast::SFV.parse_dict("")   # => {}
Fast::SFV.parse_dict([])   # => {}
Fast::SFV.parse_item("")   # => raises Fast::SFV::ParseError
```

- `parse_list("")` and `parse_list([])` → `[]` — the empty List (RFC 9651 §4.2.1 step 3).
- `parse_dict("")` and `parse_dict([])` → `{}` — the empty Dictionary (RFC 9651 §4.2.2 step 3).
- `parse_item("")` raises `ParseError` — an Item cannot be empty (RFC 9651 §4.2.3.1).

## Walk the result

List members: `Item` or `InnerList`; inner-list members are `Item`s.

`InnerList#items` is the frozen Array of member Items; `InnerList#params` belongs to the list itself — member Items carry their own (RFC 9651 §3.1.1).

`Item#params` is an ordered frozen Hash; a `;key` with no `=` holds `true` (RFC 9651 §4.2.3.2 step 2.5).

```ruby
require "fast/sfv"

list = Fast::SFV.parse_list("(\"foo\"; a=1;b=2);lvl=5, (\"bar\" \"baz\");lvl=1")
list[0].class  # => Fast::SFV::InnerList
list[0].items[0].params  # => {"a"=>1, "b"=>2}
list[0].params  # => {"lvl"=>5}
```

Duplicate keys (parameters and dictionary members alike) keep the first position and the last value — exactly Ruby Hash assignment (RFC 9651 §4.2.3.2 step 2.7 and §4.2.2 step 2.4).

```ruby
require "fast/sfv"

dict = Fast::SFV.parse_dict("a=1, a=2")
dict["a"].value  # => 2
dict.keys        # => ["a"]
```

Items with no parameters share one frozen empty Hash — `params.frozen?` is always true and `params.equal?` may match across items.

Everything reachable from a parse result is deep-frozen: the containers, the Items/InnerLists, the Hashes, every String the parse produced.

## Read each type correctly

Token vs String: a bare `sugar` is a `Fast::SFV::Token`; a quoted `"foo"` is a plain String — content equality cannot tell them apart, the class does.

```ruby
require "fast/sfv"

Fast::SFV.parse_item("sugar").value.class  # => Fast::SFV::Token
Fast::SFV.parse_item("\"sugar\"").value.class  # => String
```

A Token compares equal to the String that spells it, in both directions, and works as a Hash key:

```ruby
require "fast/sfv"

token = Fast::SFV.parse_item("sugar").value
token == "sugar"  # => true
"sugar" == token  # => true
{ "sugar" => 1 }[token]  # => 1
```

Byte sequences arrive as frozen ASCII-8BIT (`b`) Strings — compare with `.b` strings or `bytes`:

```ruby
require "fast/sfv"

value = Fast::SFV.parse_item(":aGVsbG8=:").value
value  # => "hello"
value.encoding  # => #<Encoding:ASCII-8BIT>
value == "hello".b  # => true
```

Dates: `Date#value` is the Integer delta-seconds from 1970-01-01T00:00:00Z (RFC 9651 §3.3.7).

Display strings: `DisplayString#value` is the percent-decoded UTF-8 String (RFC 9651 §3.3.8).

```ruby
require "fast/sfv"

Fast::SFV.parse_item("@1659578233").value.value  # => 1659578233
Fast::SFV.parse_item("%\"f%c3%bc\"").value.value  # => "fü"
```

See [API reference](../reference/api.md) for the full type table.

## Handle the failure

`rescue Fast::SFV::ParseError` — `#offset` is an Integer in `0..input.bytesize` (of the combined input when lines were joined).

```ruby
require "fast/sfv"

begin
  Fast::SFV.parse_item("foo bar")
rescue Fast::SFV::ParseError => e
  e.message  # => "unexpected content after the value at offset 4"
  e.offset   # => 4
end
```

`TypeError` for a wrong input type is a caller bug — fix the caller, don't rescue.

See [Diagnose a rejected field value](diagnose-failures.md).
