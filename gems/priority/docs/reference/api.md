# API reference

The definitive page for the field surface: every signature, return type, class, and rule. No prose essays (see the explanations), no how-to examples beyond one-liners. The frame codecs have their own page: [Frame payload codecs](frames.md).

## The module

`Fast::Priority`, required as `require "fast/priority"`; `Fast::Priority::VERSION` is `"0.1.0"` (`lib/fast/priority/version.rb:5`).

Ruby >= 3.4, RubyGems >= 3.5.3, exactly one runtime dependency: fast-sfv (`fast-priority.gemspec:22-23,47`).

Only the module functions and the documented classes are public: `Field` and `Scan` are `private_constant`s (`lib/fast/priority/field.rb:118,185`).

## Parsing

`Fast::Priority.parse(input) → Fast::Priority::Parameters` — §4 recipient semantics; arity 1; never raises on field content; `TypeError` for a non-String/non-Array input (`lib/fast/priority/field.rb:197`).

`Fast::Priority.parse!(input) → Fast::Priority::Parameters` — strict; arity 1; `Fast::Priority::ParseError` positioned (the wrapped Dictionary failure, or a §4 semantic violation at the effective member's value offset) (`lib/fast/priority/field.rb:210-218`).

`Fast::Priority.valid?(input) → true/false` — arity 1; never raises; false for malformed content, §4 violations, and wrong input types alike (`lib/fast/priority/field.rb:221-228`).

Input: a String (one field value) or an Array of String field lines, combined with `", "` (RFC 9651 §4.2; `lib/fast/priority/field.rb:231-234`).

## Parameters

`Fast::Priority::Parameters.new(urgency: nil, incremental: nil, unknown: nil)` — all keywords optional; an omitted (or nil) keyword means the member is absent; construction validates and raises `Fast::Priority::SerializeError` at offset 0 for: urgency not an Integer 0..7, incremental not a Boolean, unknown not a Hash, an unknown key that is not a String other than "u"/"i", an unknown value that is not an SFV Item/InnerList (`lib/fast/priority/parameters.rb:57-68,169-213`).

Readers: `urgency` (Integer 0..7, default 3 = §4.1's `DEFAULT_URGENCY`), `incremental` (Boolean, default false), `unknown` (frozen Hash, String keys → SFV Item/InnerList), `members` (the frozen ordered Hash of all held members, "u"/"i" as bare Items, unknowns as parsed) (`lib/fast/priority/parameters.rb:38,70-83,47`).

`to_s` — the canonical RFC 9651 §4.1.2 Dictionary form, `""` for no members (`lib/fast/priority/parameters.rb:89-93`).

`merge(other)` — the §8 example rule; a new frozen Parameters; TypeError for a non-Parameters argument (`lib/fast/priority/parameters.rb:102-107`).

`==` / `eql?` — canonical-wire-form equality (`to_s` equality); `hash` consistent (`lib/fast/priority/parameters.rb:110-118`).

`inspect` — `#<Fast::Priority::Parameters>` when empty, else `#<Fast::Priority::Parameters u=1, i>` (the canonical form) (`lib/fast/priority/parameters.rb:120-124`).

Frozen at construction; everything reachable is frozen (`lib/fast/priority/parameters.rb:141-147`).

## Errors

`Fast::Priority::Error < StandardError` — the family root (`lib/fast/priority/errors.rb:7`).

`Fast::Priority::ParseError < Error` — `ParseError.new(message, offset)`, `#offset`; the offset is the byte position in the combined field value (the parse's) or the member's value (the §4 check's); the frame codecs use the same class for payloads too short to carry their fixed prefix — the offset is the payload's byte size (`lib/fast/priority/errors.rb:12-26`).

`Fast::Priority::SerializeError < Error` — `SerializeError.new(message, offset)`, `#offset` (0: the check runs before anything is emitted); the whole emit path raises this and never TypeError (`lib/fast/priority/errors.rb:28-44`).

## The member type map

The Dictionary members a Priority field carries, both directions:

| member | wire example | parse holds | construction accepts |
|---|---|---|---|
| urgency `u` | `u=5` | an `Item` with Integer value 0..7 (params preserved) | `urgency:` Integer 0..7 |
| incremental `i` | `i` / `i=?1` | an `Item` with Boolean value | `incremental:` Boolean |
| unknown key | `foo=bar` | the SFV `Item`/`InnerList` as parsed | `unknown:` Hash, SFV `Item`/`InnerList` values |

Values are fast-sfv objects (`Fast::SFV::Token`, `Item`, `InnerList`) because the field is an RFC 9651 Dictionary — see the fast-sfv docs at `https://github.com/jetpks/fast-http-fields/tree/main/gems/sfv/docs`; SFV parameters on members (`u=3;q=1`) are tolerated and preserved (`test/fast/priority/field.rb:82-86`).

## Immutability and ownership

Parse results and constructed values are frozen, their member Hashes frozen (`lib/fast/priority/parameters.rb:141-147`; `test/fast/priority/field.rb:100-105`).

`to_s` answers a fresh mutable String each call.

## Requirements

Ruby >= 3.4 (CI matrix 3.4/4.0), RubyGems >= 3.5.3, one runtime dependency: fast-sfv (`fast-priority.gemspec:22-23,47`).
