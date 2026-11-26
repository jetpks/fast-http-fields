# Diagnose a rejected field value

## Read a ParseError

Message shape: `"<reason> at offset <n>"`.

`ParseError#offset` is an Integer byte position in the combined input (the lines already joined when an Array was passed), in `0..input.bytesize`.

```ruby
require "fast/sfv"

begin
  Fast::SFV.parse_item("foo bar")
rescue Fast::SFV::ParseError => e
  e.message  # => "unexpected content after the value at offset 4"
  e.offset   # => 4
end
```

The offset points at the byte where the strict parse stopped. Visualized:

```text
foo bar
   ^
   offset 4 — the space the Item grammar does not allow
```

## Read a SerializeError

`SerializeError#offset` is an Integer byte position in the output built so far — a different axis than ParseError's; `0` when the top-level shape itself was wrong.

```ruby
require "fast/sfv"

begin
  Fast::SFV.serialize_list([Fast::SFV::Item.new(1, {}), 42])
rescue Fast::SFV::SerializeError => e
  e.message  # => "a list member must be an Item or an InnerList (got Integer) at offset 3"
  e.offset   # => 3
end

begin
  Fast::SFV.serialize_item(:foo)
rescue Fast::SFV::SerializeError => e
  e.message  # => "an Item is required (got Symbol)"
  e.offset   # => 0
end
```

Offset 3 is the position in `"1, "` where the bad member would have been emitted. Offset 0 means nothing was emitted — the top-level shape was wrong. Positioned errors carry `"… at offset <n>"`; top-level shape errors do not.

The whole emit path raises `SerializeError` and never `TypeError` — on emit the wrongness is in the value tree being sent, which is field content, not a caller protocol bug.

## Rescue the family root

Every `Fast::SFV` failure descends from `Fast::SFV::Error < StandardError`; one rescue guards the whole surface.

```ruby
require "fast/sfv"

begin
  Fast::SFV.parse_item("foo bar")
rescue Fast::SFV::Error => e
  e.message  # => "unexpected content after the value at offset 4"
end
```

`TypeError` on the parse side is deliberately outside the family — it flags caller bugs that should be fixed, not field content to report.

## Why there is no lenient mode

RFC 9651 §1.1 forbids tolerance deliberately — leniency breeds divergent workarounds and interoperability/security failures; §1.2 demands behavior indistinguishable from the algorithms. See [Why parsing and serialization are strict](../explanation/strictness.md).
