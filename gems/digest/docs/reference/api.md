# API reference

The definitive page for the whole surface: every signature, return type, class, and rule. No prose essays (see the explanations), no how-to examples beyond one-liners inside tables. The registry table has its own page: [The hash algorithm registry](algorithms.md).

## The module

`Fast::Digest`, required as `require "fast/digest"`; `Fast::Digest::VERSION` is `"0.1.0"` (`lib/fast/digest/version.rb:5`).

Inside this module a bare `Digest` resolves to `Fast::Digest`, so the gem's own stdlib references spell `::Digest::SHA256` — user code at the top level spells `Digest::SHA256` plainly (`lib/fast/digest/registry.rb:3-7`; `lib/fast/digest.rb:71-73`).

Ruby >= 3.4, RubyGems >= 3.5.3, exactly one runtime dependency: fast-sfv, plus the stdlib digest library (a default gem) (`fast-digest.gemspec:25-26,47-50`).

Only the four field classes, the registry functions and the errors are public: `Field` and `Scan` are `private_constant`s (`lib/fast/digest/fields.rb:145,386`).

## The four field classes

`Fast::Digest::ContentDigest` (§2), `Fast::Digest::ReprDigest` (§3), `Fast::Digest::WantContentDigest` and `Fast::Digest::WantReprDigest` (§4):

| field class | RFC section | member value constraint | `.of` |
|---|---|---|---|
| `ContentDigest` | §2 | Byte Sequence (`String` tagged ASCII-8BIT) | yes |
| `ReprDigest` | §3 | Byte Sequence (`String` tagged ASCII-8BIT) | yes |
| `WantContentDigest` | §4 | Integer 0..10 | no |
| `WantReprDigest` | §4 | Integer 0..10 | no |

The two Integrity classes carry `.of(algorithm, bytes)` — compute-and-construct (`lib/fast/digest/fields.rb:420-422,454-456`); the two preference classes carry none — preferences are a hint, selection is caller policy (`lib/fast/digest/fields.rb:459-465`).

## Parsing

`<Field>.parse(input) → <Field>` — the frozen value object; §2/§3/§4 recipient semantics; never raises on field content — malformed field or ANY constraint-violating member answers the ENTIRE-field-ignored empty value (RFC 9651 §2.2; `lib/fast/digest/fields.rb:158-176`); `TypeError` for a non-String/non-Array input.

`<Field>.parse!(input) → <Field>` — the frozen value object, strict: the wrapped Dictionary failure, then the first member breaking the field's constraint, raised as `ParseError` positioned at that member's VALUE in the combined field value — the last-wins member (`lib/fast/digest/fields.rb:188-194,222-231`).

`<Field>.valid?(input) → Boolean` — true/false; never raises; false for malformed content, constraint violations, and wrong input types alike (`lib/fast/digest/fields.rb:200-205`).

Input: a String (one field value) or an Array of String field lines, combined with ", " (RFC 9651 §4.2; `lib/fast/digest/fields.rb:209-214`).

## The value object

Readers:

- `members` — the frozen ordered Hash of algorithm key => `Fast::SFV::Item`, parameters preserved (`lib/fast/digest/fields.rb:253`)
- `keys` — frozen, held order (`lib/fast/digest/fields.rb:256`)
- `[](key)` — the bare value — the digest bytes or the preference Integer; nil for an absent key (`lib/fast/digest/fields.rb:283-285`)
- `key?(key)`, `size`, `empty?`, `each` — yields key and bare value (`lib/fast/digest/fields.rb:288-305`)

`to_s → String` — the canonical RFC 9651 §4.1.2 Dictionary serialization, `""` when none are held; never raises (a parsed value re-emits its canonical form — non-canonical spacing normalizes, the erratum's doubled padding re-emits single) (`lib/fast/digest/fields.rb:307-316`).

`==` / `eql? → Boolean` — canonical-wire-form equality WITHIN the field class: `other.instance_of?(self.class) && to_s == other.to_s`; a ContentDigest never equals a ReprDigest; `hash` consistent (`lib/fast/digest/fields.rb:318-331`).

`inspect → String` — `#<Fast::Digest::ReprDigest>` when empty, else `#<Fast::Digest::ReprDigest sha-256=:…=:>` (the canonical form) (`lib/fast/digest/fields.rb:333-336`).

Frozen at construction; the members Hash, the keys view and the member value Strings are frozen; `to_s` answers a fresh mutable String each call (`lib/fast/digest/fields.rb:343-347,266-278`).

## Construction

`<Field>.new(members = {}) → <Field>` — a Hash of algorithm key => bare value: a String tagged ASCII-8BIT (and not a `Fast::SFV::Token`) for the Integrity fields, an Integer 0..10 for the preference fields; keys Structured Fields keys (lcalpha or "*" first byte, continuing lcalpha/DIGIT/_-/.*). Anything else raises `SerializeError` at offset 0 before a member is built; the empty Hash builds the empty value (`lib/fast/digest/fields.rb:258-278,360-384`).

Value Strings are frozen IN PLACE as part of the value object — pass a copy if the buffer is reused (`lib/fast/digest/fields.rb:266-268`).

## The registry functions

| method | signature | returns | unknown key |
|---|---|---|---|
| `registered?` | `(key) → Boolean` | true/false | false |
| `status` | `(key) → String\|nil` | "Active" / "Deprecated" / nil | nil |
| `active?` | `(key) → Boolean` | true/false | false |
| `deprecated?` | `(key) → Boolean` | true/false | false |
| `computable?` | `(key) → Boolean` | true only for sha-256, sha-512, md5, sha | false |
| `compute` | `(key, input) → String` | the stdlib's digest bytes, frozen ASCII-8BIT String | raises `Error` |

`Fast::Digest.registered?(key)`, `status(key)`, `active?(key)`, `deprecated?(key)`, `computable?(key)` (`lib/fast/digest/registry.rb:57-89`). `Fast::Digest.compute(key, input)` — the stdlib's bytes as a frozen ASCII-8BIT String, TypeError for a non-String input, `Fast::Digest::Error` naming the key for the checksum entries and unknown keys (`lib/fast/digest/registry.rb:55-121`). The registry table itself: [The hash algorithm registry](algorithms.md).

## Errors

`Fast::Digest::Error < StandardError` — the family root, raised in its own right by `compute` and the `.of` helpers (a usage failure — neither a parse nor a serialization defect) (`lib/fast/digest/errors.rb:5-16`).

`Fast::Digest::ParseError < Error` — `ParseError.new(message, offset)`, `#offset`; the byte position in the combined field value (the wrapped Dictionary failure's, or the offending member's value) (`lib/fast/digest/errors.rb:18-35`).

`Fast::Digest::SerializeError < Error` — `SerializeError.new(message, offset)`, `#offset` (0: the checks run before anything is emitted); the whole emit path raises this and never TypeError (`lib/fast/digest/errors.rb:37-54`).

One `rescue Fast::Digest::Error` guards every field-content and usage failure; a wrong input type is a caller bug and raises plain TypeError.

## The member type map

The Dictionary members a Digest field carries, both directions:

| member | wire example | parse holds | construction accepts |
|---|---|---|---|
| Integrity value | `sha-256=:RK/0qy…=:` | an `Item` with a Byte Sequence value (a frozen ASCII-8BIT String; parameters preserved) | a String tagged ASCII-8BIT |
| preference value | `sha-256=10` | an `Item` with an Integer 0..10 value | an Integer 0..10 |
| unknown key | `sha-3=:AAAA:` | the SFV `Item` as parsed | an SFV-legal value for that field's constraint |

Values are fast-sfv objects (`Fast::SFV::Item`) because the field IS an RFC 9651 Dictionary — see the fast-sfv docs at `https://github.com/jetpks/fast-http-fields/tree/main/gems/sfv/docs`; SFV parameters on members (`sha-256=:…=:;q=1`) are tolerated and preserved (`test/fast/digest/fields.rb:143-148`).

## How the surface is verified

The vectors: RFC 9530's own appendices as quoted test vectors — B.1 through B.11's field values, C.1's preferences, Appendix D's eight sample digests against the stdlib ground truth, the erratum's doubled padding — frozen in the suite (`test/fast/digest/fields.rb`, 394 lines).

The suite totals at writing: 3079 passed / 4772 assertions at the monorepo root, every gem's suites green together (`bundle exec sus`; the docs iteration adds no tests). This is the only leaf carrying the suite totals.

## Requirements

Ruby >= 3.4, RubyGems >= 3.5.3, one runtime dependency (fast-sfv), the stdlib digest library (`fast-digest.gemspec:25-26,47-50`).
