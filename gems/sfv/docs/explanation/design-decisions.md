# Design decisions in fast-sfv

The implementation choices that shape the values you parse and emit,
each with the alternative that was rejected. The theme through all of
them: the Ruby type or tag IS the wire-type tag, so a value that
round-trips needs no second bookkeeping.

## Strict in both directions

RFC 9651 §1.1 forbids tolerance: the specification "intentionally
defines strict parsing and serialization behaviors using step-by-step
algorithms; the only error handling defined is to fail the entire
operation altogether" — and a field specification is not allowed to
loosen the requirement. So the parse raises `Fast::SFV::ParseError`
with the byte offset where it stopped, and the family principle
lands on its strict side for this gem, because fast-sfv IS the
syntax layer.

The emit is strict for the mirror-image reason: a sender never puts
on the wire a value that is not a Structured Field Value — §1.2
requires parse behavior indistinguishable from the RFC's algorithms,
and allows emit variation only where the output still parses back,
which rules out inventing a wire form. There is no coercion on the
way out either: `serialize_item` on a
`Symbol` raises `SerializeError` rather than guessing a token, and an
sf-string value with high bytes raises rather than being
percent-encoded into a Display String.

```ruby
Fast::SFV.serialize_item(Fast::SFV::Item.new(:sugar, {})) # raises Fast::SFV::SerializeError
Fast::SFV.serialize_item(Fast::SFV::Item.new("fü", {})) # raises Fast::SFV::SerializeError
```

## The Token ruling: the class is the tag

Tokens were first mapped to `Symbol` — the shape starry, the vendored
RFC 8941 reference implementation, answers to this day
(`lib/starry/parser.rb:168` ends its token scan in `.to_sym`). The
Symbol mapping was replaced by a frozen `Fast::SFV::Token < String`
in a logged decision (2026-11-25, iteration `sfv-token-type`), and
the operators ruled it: the day-one idioms are String idioms, and a
Symbol fails them.

`==` is the one that matters most. A parsed dictionary member is
compared against a String literal — the value behind the `error` key
against `"unavailable"` — and that must be true, in both directions,
without a `.to_s` in sight. The rest of the day-one surface follows
the same pressure: Ruby's own culture reads parsed identifiers as
Strings (`JSON.parse` never symbolizes keys by default), `send` takes
a String method name as happily as a Symbol, and JSON generation
answers a JSON string for a String. A `String` subclass carries the
type tag without giving up any String behavior:

```ruby
require "json"

token = Fast::SFV.parse_item("upcase").value
token.class # => Fast::SFV::Token
token == "upcase" # => true
"upcase" == token # => true
"hello".send(token) # => "HELLO"
JSON.generate(token) # => "\"upcase\""
```

The class is the distinction, so the class is what the parse and emit
paths dispatch on — a quoted string parses to a plain `String`, a
token to a `Token`, a plain `String` emits quoted, a `Token` emits
bare. The content never decides, which also settles the `Symbol`
question on the emit side: after the switch a `Symbol` is simply
wrong-typed input.

This is a deliberate, documented divergence from starry — verified
against the vendored 0.2.0 gem, not assumed. The divergence and the
8941 subset both libraries implement are laid out in
[RFC 9651 vs RFC 8941](rfc-9651-vs-8941.md).

### No intern cache

A repeated token value builds its own `Token`. An intern cache —
one shared `Token` per token string ever seen — would save one object
per repeated value, and was measured before being rejected: a token
value costs its content slice plus the `Token` built from it, one
object more than the slice alone, the same worst case the Symbol path
paid for a fresh Symbol. The saving is a per-value constant,
nowhere near a budget demand, and a cache would trade a global table
and its invalidation for it. The budget numbers are frozen in
`test/fast/sfv/allocations.rb` — a token bare item is 4.

## The Byte Sequence ruling: the encoding is the tag

A byte sequence could have been a wrapper type — a `ByteSequence`
class saying "these are bytes" the way `Fast::SFV::Date` says "this
is a date". That alternative was considered and rejected, because it
breaks the day-one idiom: a digest you just computed compares equal,
bytewise, with the one that arrived on the wire. `Digest` answers an
ASCII-8BIT `String`; if the parse answered a wrapper, every digest
check would unwrap first:

```ruby
require "digest"

body = "the request body"
parsed = Fast::SFV.parse_item(":#{[Digest::SHA256.digest(body)].pack("m0")}:")
parsed.value == Digest::SHA256.digest(body) # => true
```

So a byte sequence is a `String` tagged `Encoding::ASCII_8BIT`
(BINARY), and the tag — never the content — is what says bytes. The
cost of the tag-as-distinction is the corner cases, and they are
mitigated rather than hidden: string values, dictionary keys and
display strings are always forced to UTF-8 on the way in, so a BINARY
answer from the parse means bytes; a byte sequence is the only value
that is always BINARY. The one value that can carry a binary tag in
from its source is a token — a `Token` sliced out of a
binary-tagged input keeps that tag, and still emits bare, because the
emit reads the class first. Both corners are worked through in
[Work with byte sequences](../how-to-guides/work-with-byte-sequences.md).

## Decimal is Float, not BigDecimal

An SFV decimal is bounded — at most 12 integer digits and 3 fraction
digits — so every representable value is smaller than 2^53 and a
binary double holds it exactly. `BigDecimal` would add a dependency
on precision that is already there, so the mapping is `Float`. The
emit writes the digits as `Float#to_s` spells them, rounded to three
fraction places with ties to even — the as-written reading the
conformance corpus's tie records pin.

## The minimal wrappers

`Date` and `DisplayString` are minimal frozen wrappers because their
wire forms need a distinguishing mark that a bare Ruby value cannot
carry: `Integer` cannot be subclassed, so a date cannot be an
`Integer` subclass the way a token is a `String` subclass, and a
display string must be told apart from an sf-string because only one
of them may carry non-ASCII content. Plain `Integer` and `String`
keep their unmarked wire forms, so a wrapper exists exactly where the
round-trip demands the tag — and nowhere else.

## Frozen value objects

Every parse result is deep-frozen: the `Item`s and `InnerList`s, the
list `Array`, the dictionary and parameter `Hashes` with their
`String` keys, and every `String` the parse produced. A frozen value
cannot be mutated, so it is safe to share across threads and to hold
in a constant without copying, and a caller cannot corrupt a shared
parse result. Items with no parameters share one frozen empty `Hash`
— nothing can mutate it, so sharing is free.

```ruby
result = Fast::SFV.parse_dict("a=1")
result.frozen? # => true
result["a"].frozen? # => true
result["a"].params.frozen? # => true
```

## Byte-index scanners, budgets as tests

The parse walks the input by byte index with 256-entry character
class tables — no regex per token, no scan pointer object — and the
emit appends bytes into one output `String`, which is the only object
an emission allocates. The allocation cost of both paths is frozen
into the suite as budgets (`test/fast/sfv/allocations.rb`): a bare
item parses in 2 objects, a token bare item 4, an item with
parameters 8, a string item 3, a byte sequence item 3, a display
string item 4, a three-token list 11, a multi-line list 5, a mixed
dictionary 11; a bare item serializes in 1, an item with parameters
1, a decimal item 2, a list 1, a dictionary 1. A regression that
allocates more fails the suite. The measured throughput behind those
budgets is in [Performance and allocations](performance.md).

## Zero runtime dependencies

The gemspec declares no runtime dependencies. fast-sfv is the family
substrate — the four other field gems in fast-http-fields declare
exactly `fast-sfv` as their only runtime dependency — so a dependency
here would multiply through the whole family. The comparison gem
(starry) and the timing harness live only in the benchmark bundle,
behind an explicit `BUNDLE_GEMFILE`, never in the test or CI bundle.

## Where to go next

- [Type mapping — RFC 9651 to Ruby](../reference/type-mapping.md) —
  the table these rulings produce.
- [Performance and allocations](performance.md) — the measured side
  of the budgets.
- [RFC 9651 vs RFC 8941](rfc-9651-vs-8941.md) — the subset and the
  divergence in context.
