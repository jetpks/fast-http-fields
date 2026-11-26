# Conformance and the httpwg corpus

## Scope

fast-sfv implements RFC 9651 §4.1 (Serializing) and §4.2 (Parsing) in full — all eight bare item types, parameters, inner lists, lists, dictionaries, the Boolean-true short forms, the empty-container field omission, the field-line combining.

Processing is intentionally strict, per RFC 9651 §1.1 (no tolerance, fail the whole operation) and §1.2 (behavior indistinguishable from the algorithms).

Dates (RFC 9651 §3.3.7) and Display Strings (RFC 9651 §3.3.8) are RFC 9651 additions beyond the RFC 8941 subset the reference implementation covers (RFC 9651 Appendix D).

## Grammar coverage map

| RFC algorithm | parse | serialize |
|---|---|---|
| §4.2 Parsing (steps 1–8) | `Parser#item`/`#list`/`#dictionary` + `check_ascii`/`check_end` | §4.1 Serializing (steps 1–5) — the three entry points |
| §4.2.1 List / §4.2.1.2 Inner List | `list_members`, `inner_list` | §4.1.1 List / §4.1.1.1 Inner List — `list_string`, `emit_inner_list` |
| §4.2.2 Dictionary | `dictionary_members` | §4.1.2 Dictionary — `dictionary_string` |
| §4.2.3 Item / §4.2.3.1 Bare Item / §4.2.3.2 Parameters / §4.2.3.3 Key | `item_member`, `parse_bare_item`, `parse_parameters`, `parse_key` | §4.1.3 / §4.1.3.1 / §4.1.1.2 / §4.1.1.3 — `emit_item`, `emit_bare_item`, `emit_parameters`, `emit_key` |
| §4.2.4 Integer or Decimal | `parse_number` | §4.1.4 / §4.1.5 — `emit_integer`, `emit_decimal` |
| §4.2.5 String | `parse_string` | §4.1.6 — `emit_string` |
| §4.2.6 Token | `parse_token` | §4.1.7 — `emit_token` |
| §4.2.7 Byte Sequence | `parse_byte_sequence`, `decode_bytes` | §4.1.8 — `emit_byte_sequence` |
| §4.2.8 Boolean | `parse_boolean` | §4.1.9 — the `true`/`false` arms |
| §4.2.9 Date | `parse_date` | §4.1.10 — `emit_date` |
| §4.2.10 Display String | `parse_display_string` | §4.1.11 — `emit_display_string` |

## The httpwg structured-field-tests corpus

Vendored byte-frozen under `test/corpus/` from `https://github.com/httpwg/structured-field-tests` at commit `4a4782f8234512af133f6f57c4ca998578b57110` ("Merge pull request #131 from apasel422/base32"), 2025-11-25 UTC clone; `LICENSE.md` (IETF Trust terms) retained per its redistribution terms; never edited in place (`test/corpus/PROVENANCE.md`).

Record semantics: `name`, `raw` (array of field lines), `header_type` ("item"/"list"/"dictionary"), `expected`, `must_fail`, `can_fail`, `canonical`; decimals compare as written (`test/corpus/README.md`).

The corpus encodes byte sequences as base32 (RFC 4648 §6) in `expected`; the wire is base64 (RFC 4648 §4).

## What the harness asserts

Parse side: every record runs through the entry point its `header_type` names, with `raw` (the Array of lines) as the input — the corpus itself exercises the `", "` combining; `expected` must match through a strict translation (tokens to `Token`, base32 binaries decoded, dates and display strings through `#value`, parameters and dictionaries as ordered pairs); `must_fail` records must raise `ParseError` whose `#offset` is an Integer in `0..joined-input.bytesize`.

A raise on a non-`must_fail` record is only acceptable where the corpus marked it `can_fail` (the RFC's SHOULD-level leniency).

Serialize side: the four `serialisation-tests/` files build each record's `expected` into a value tree — a `must_fail` record cannot be serialized; the others must canonicalize to `canonical[0]`.

Round trips: every non-`must_fail` parse record re-serializes to its `canonical` (or its raw line), with the empty array meaning the omitted field — answered as `nil`.

The 125 `token-generated` `must_fail` records carry token values that fail the token grammar itself, so their value trees cannot be built: `Token.new`'s `ArgumentError` satisfies "the value cannot be serialised" at the boundary.

## Counts

Counted directly from the vendored files:

| count | value |
|---|---|
| parse-side JSON files | 20 |
| parse records | 1607 |
| must_fail parse records | 873 |
| can_fail parse records | 8 |
| round-trip candidates (1607 − 873) | 734 |
| serialisation-tests files | 4 |
| serialisation records | 553 |
| serialisation must_fail (125 token-generated unbuildable + 418 buildable) | 543 |
| serialisation records that must canonicalize | 10 |
| suite totals at regeneration time | 2947 passed, 4268 assertions |

Re-count: `for f in test/corpus/*.json; do ruby -rjson -e 'puts JSON.parse(File.read(ARGV[0])).size' "$f"; done` summed to 1607; same over `test/corpus/serialisation-tests/*.json` to 553; must_fail splits via `record["must_fail"]`.

`schema/` (4 JSON-schema files) is vendored but inert to the harness.

## Divergences and edge readings

- **Tokens are `Fast::SFV::Token`, not Symbols** — a deliberate, documented divergence from starry, the RFC 8941 reference implementation, which returns `Symbol` tokens; the class is the wire-type tag. See [Why the Ruby type is the wire-type tag](../explanation/wire-type-tag.md).

- **Base64 padding is synthesized on parse:** unpadded, over-padded and dirty-padded values decode, per RFC 9651 §4.2.7 step 7 and its SHOULDs; a character outside the alphabet, a misplaced pad or a lone trailing character fails.

- **Duplicate parameter and dictionary keys overwrite at the first position,** keeping the last value — Ruby Hash assignment is exactly the RFC §4.2.3.2 step 2.7 / §4.2.2 step 2.4 behavior.

- **Decimal emission reads the digits as written** (the shortest round-trip `Float#to_s`), rounded to three places, ties to even — the corpus's tie records pin this reading over the binary double's.
