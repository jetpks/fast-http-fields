# fast-sfv

fast-sfv implements RFC 9651 Structured Field Values for Ruby — Items,
Lists, and Dictionaries with parameters — the syntax substrate every
other fast-http-fields gem builds on.

- **Strict both ways.** The RFC 9651 §4.2 parse and the §4.1 canonical
  emit, no tolerance in either direction, positioned
  `Fast::SFV::ParseError` and `Fast::SFV::SerializeError`.
  [Getting started](docs/tutorials/getting-started.md).
- **The type is the tag.** A `Fast::SFV::Token` is a token, a plain
  `String` a quoted sf-string, a binary-tagged `String` a byte
  sequence — the content never decides.
  [Type mapping](docs/reference/type-mapping.md).
- **Corpus-green.** The vendored httpwg conformance corpus — 1607
  parse records, 553 serialisation-tests records, 734 parse-side
  round trips — pins every grammar edge.
- **Allocation budgets as tests.** The parse and emit costs are
  frozen into the suite as budgets.
  [Performance and allocations](docs/explanation/performance.md).
- Zero runtime dependencies. Requires Ruby `>= 3.4`. MIT.

## Quickstart

Install from RubyGems `gem install fast-sfv` or add `gem "fast-sfv"`
to your Gemfile.

The require is `fast/sfv`, not `fast-sfv`.

```ruby
require "fast/sfv"

item = Fast::SFV.parse_item("42;a=1")
item.value  # => 42
item.params # => {"a" => 1}

Fast::SFV.serialize_list(Fast::SFV.parse_list("1, 42")) # => "1, 42"
Fast::SFV.serialize_dict("a" => Fast::SFV::Item.new(1, {})) # => "a=1"

Fast::SFV.parse_item("42 42") # raises Fast::SFV::ParseError
Fast::SFV.valid_item?("42 42") # => false
```

Parsing is strict — RFC 9651 §1.1 forbids tolerance — so a malformed
field raises `Fast::SFV::ParseError` carrying `#offset`, the byte
position where the parse stopped; the `valid_item?`, `valid_list?`
and `valid_dict?` mirrors answer the same question with a boolean and
never raise. Serializing is strict too: the Ruby type of a value is
its wire-type tag, an empty List or Dictionary serializes to `nil`
(the field is omitted entirely), and anything non-serializable
raises positioned `Fast::SFV::SerializeError`. Every entry point
takes a String or an Array of the field's lines, combined per
RFC 9651 §4.2.

## Documentation

- Tutorial:
  - [Getting started with fast-sfv](docs/tutorials/getting-started.md)
- How-to guides:
  - [Parse or emit?](docs/how-to-guides/parse-vs-emit.md)
  - [Work with byte sequences](docs/how-to-guides/work-with-byte-sequences.md)
  - [Handle multi-line fields](docs/how-to-guides/handle-multi-line-fields.md)
  - [Combine fields from h1, h2, h3 and Rack](docs/how-to-guides/combine-fields-from-transports.md)
- Reference:
  - [Fast::SFV — API reference](docs/reference/api.md)
  - [Type mapping — RFC 9651 to Ruby](docs/reference/type-mapping.md)
- Explanation:
  - [Design decisions in fast-sfv](docs/explanation/design-decisions.md)
  - [Performance and allocations](docs/explanation/performance.md)
  - [RFC 9651 vs RFC 8941](docs/explanation/rfc-9651-vs-8941.md)

## Tokens

A token value parses to `Fast::SFV::Token` — a frozen `String`
subclass whose class is the wire-type tag. The content is plain
String semantics: `Token.new("bar") == "bar"` in both directions, it
hashes as its content, `to_s` is the bare wire form, and it goes
wherever a String goes — `send` accepts it, JSON generates it as a
JSON string — so the day-one idioms hold:

```ruby
require "json"

parsed = Fast::SFV.parse_dict("error=unavailable")
parsed["error"].value == "unavailable" # => true

token = Fast::SFV.parse_item("upcase").value
"hello".send(token) # => "HELLO"
JSON.generate(token) # => "\"upcase\""
```

The class is the distinction: a quoted sf-string parses to a plain
String, a bare token to a `Token`, and the serializer dispatches on
the same tag — a String emits quoted, a `Token` emits bare (the Token
arm reads before the byte-sequence branch, so a binary-tagged source
still emits bare), and a `Symbol` raises `SerializeError` as
wrong-typed input:

```ruby
Fast::SFV.serialize_item(Fast::SFV::Item.new("foo", {})) # => "\"foo\""
Fast::SFV.serialize_item(Fast::SFV::Item.new(Fast::SFV::Token.new("foo"), {})) # => "foo"
Fast::SFV.serialize_item(Fast::SFV::Item.new(Fast::SFV::Token.new("foo".b), {})) # => "foo"
Fast::SFV.serialize_item(Fast::SFV::Item.new("foo".b, {})) # => ":Zm9v:"
Fast::SFV.serialize_item(Fast::SFV::Item.new(:foo, {})) # raises Fast::SFV::SerializeError
```

Construction is the boundary: `Token.new` validates the whole token
grammar (RFC 9651 §3.3.4 — ALPHA or `*` first, then tchar, `:` and
`/`) and raises `ArgumentError` otherwise, with no length cap.

This is a deliberate divergence from starry (the vendored RFC 8941
reference implementation the benchmark compares against), which
returns `Symbol` for tokens: Ruby's own culture reads parsed
identifiers as Strings — `JSON.parse` never symbolizes keys by
default — and a String subclass carries the tag without giving up
String behavior. The ruling and its history are in
[Design decisions](docs/explanation/design-decisions.md).

## Compatibility

- Ruby `>= 3.4`; no runtime dependencies.
- MIT license — see [LICENSE](../../LICENSE).
- Source and changelog at
  [github.com/jetpks/fast-http-fields](https://github.com/jetpks/fast-http-fields).

Install and compatibility details are authoritative in
[`fast-sfv.gemspec`](fast-sfv.gemspec) and
[`.github/workflows/ci.yml`](../../.github/workflows/ci.yml).
