# fast-sfv

fast-sfv is the RFC 9651 Structured Field Values implementation for Ruby: strict parse, canonical emit, frozen value objects, zero runtime dependencies.

## What it is

Implements RFC 9651 Structured Field Values — Items, Lists, Dictionaries with parameters — the syntax layer the rest of the fast-http-fields family builds on. Every other field gem parses and emits through Structured Field Values.

Three parse entry points (`parse_item`/`parse_list`/`parse_dict`) with total `valid_*?` mirrors; three serialize entry points (`serialize_item`/`serialize_list`/`serialize_dict`).

Pure Ruby, hand-rolled byte-index scanning, deep-frozen results, no runtime dependencies.

MIT license. Source at `https://github.com/jetpks/fast-http-fields`.

## Installation

```sh
gem install fast-sfv
```

In a Gemfile:

```ruby
gem "fast-sfv"
```

Require path is `fast/sfv`:

```ruby
require "fast/sfv"
```

Requires Ruby >= 3.4 and RubyGems >= 3.5.3. No other runtime requirement.

## Quickstart

Parse a dictionary, read it, and emit it back:

```ruby
require "fast/sfv"

dict = Fast::SFV.parse_dict("a=1, b;foo=bar, c=(1 2)")
dict.keys        # => ["a", "b", "c"]
dict["a"].value  # => 1
dict["c"].items.map(&:value)  # => [1, 2]

Fast::SFV.serialize_dict(dict)  # => "a=1, b;foo=bar, c=(1 2)"
```

Malformed content raises with a byte offset:

```ruby
require "fast/sfv"

begin
  Fast::SFV.parse_item("foo bar")
rescue Fast::SFV::ParseError => e
  e.offset  # => 4
end
```

Next: the [tutorial](docs/tutorials/structured-fields.md) for the guided path.

## Strict by design

- Field content that is not a Structured Field Value of the asked shape raises `Fast::SFV::ParseError` carrying the byte offset where the parse stopped.
- An input that is neither a String nor an Array of field lines raises `TypeError` — a caller bug, not field content.
- Any non-serializable value raises `Fast::SFV::SerializeError` with the byte offset into the output built so far; `TypeError` never appears on the emit path.
- `valid_item?`, `valid_list?`, `valid_dict?` answer the same question with a boolean and never raise.

See [Diagnose a rejected field value](docs/how-to-guides/diagnose-failures.md) and [Why parsing and serialization are strict](docs/explanation/strictness.md).

## Documentation

Current release 0.1.0. Changelog at [CHANGELOG.md](CHANGELOG.md). The docs tree is also linked from the gemspec metadata `documentation_uri`.

### Tutorial

- [Your first Structured Field Values](docs/tutorials/structured-fields.md) — Parse an Item, a List, a Dictionary; meet the eight bare item types; emit a value back; meet the errors.

### How-to guides

- [Parse a field value](docs/how-to-guides/parse-field-values.md) — Choose the entry point, pass one line or many, walk the result, handle the failure.
- [Serialize a field value](docs/how-to-guides/serialize-field-values.md) — Serialize what you parsed, build values by hand, pick wire types, use short forms, respect the limits.
- [Validate a field value without exceptions](docs/how-to-guides/validate-field-values.md) — Answer "is this a Structured Field Value?" with `valid_item?`/`valid_list?`/`valid_dict?` and no exceptions.
- [Diagnose a rejected field value](docs/how-to-guides/diagnose-failures.md) — Read a `ParseError`/`SerializeError` byte offset and turn it into a diagnosis.

### Reference

- [API reference](docs/reference/api.md) — The complete public surface: every method, class, error, input/output shape, with signatures and return types.
- [Conformance and the httpwg corpus](docs/reference/conformance.md) — RFC 9651 conformance scope, the grammar coverage map, and the vendored httpwg corpus (provenance, semantics, counts).

### Explanation

- [Why parsing and serialization are strict](docs/explanation/strictness.md) — Why both directions are strict, and why the failures split into `TypeError`, `ParseError`, and `SerializeError`.
- [Why the Ruby type is the wire-type tag](docs/explanation/wire-type-tag.md) — Why the Ruby type of a value is its wire-type tag — the `Token < String` design, the ASCII-8BIT byte-sequence tag, and the starry divergence.
- [Performance and allocation budgets](docs/explanation/performance.md) — How the parser and serializer stay allocation-lean; the benchmark table and allocation budgets, with the measurement methodology and caveats.
