# fast-sfv

fast-sfv implements RFC 9651 Structured Field Values for Ruby — Items,
Lists, and Dictionaries with parameters — the syntax substrate every
other fast-http-fields gem builds on.

> **Parse and serialize landed.** `Fast::SFV.parse_item`, `parse_list`
> and `parse_dict` implement the strict RFC 9651 §4.2 parse — Items,
> Lists and Dictionaries with parameters and inner lists, all eight
> bare item types — and `Fast::SFV.serialize_item`, `serialize_list`
> and `serialize_dict` emit the canonical §4.1 wire form from the same
> value shapes, against the vendored httpwg conformance corpus (1607
> parse records and 1287 serialize records under `test/corpus/`). The
> docs tree and the 0.1.0 release arrive with the next iterations.

```ruby
Fast::SFV.serialize_list(Fast::SFV.parse_list("1, 42"))          # => "1, 42"
Fast::SFV.serialize_dict("a" => Fast::SFV::Item.new(1, {}))      # => "a=1"
```

## Tokens

A token value parses to `Fast::SFV::Token` — a frozen `String` subclass
whose class is the wire-type tag. The content is plain String semantics:
`Token.new("bar") == "bar"` in both directions, it hashes as its content,
`to_s` is the bare wire form, and it goes wherever a String goes — `send`
accepts it, JSON generates it as a JSON string — so the day-one idioms
hold:

```ruby
parsed = Fast::SFV.parse_dict("error=unavailable")
parsed["error"].value == "unavailable"  # => true, a Token by content
```

The class is the distinction: a quoted sf-string parses to a plain
String, a bare token to a `Token`, and the serializer dispatches on the
same tag — a String emits quoted, a `Token` emits bare (the Token arm
reads before the byte-sequence branch, so a binary-tagged source still
emits bare), and a Symbol now raises `SerializeError` as wrong-typed
input. Construction is the boundary: `Token.new` validates the whole
token grammar (RFC 9651 §3.3.4 — ALPHA or `*` first, then tchar, `:` and
`/`) and raises `ArgumentError` otherwise, with no length cap.

This is a deliberate divergence from starry (the vendored RFC 8941
reference implementation the benchmark compares against), which returns
`Symbol` for tokens: Ruby's own culture reads parsed identifiers as
Strings — `JSON.parse` never symbolizes keys by default — and a String
subclass carries the tag without giving up String behavior.

The require is `fast/sfv`, not `fast-sfv`. Requires Ruby `>= 3.4`. No
runtime dependencies.
