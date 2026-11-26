# Changelog

## 0.1.0 (2026-11-26)

- Fields: `Fast::Digest::ContentDigest`, `ReprDigest`, `WantContentDigest` and
  `WantReprDigest` — the four RFC 9530 fields as frozen value objects over
  fast-sfv, each with the family mechanics: `parse` fail-closed (a malformed
  field, or any member violating the field's constraint, is the entire field
  ignored per RFC 9651 §2.2 — the empty value, the same answer an absent
  field gives), `parse!` positioned strict truth (the wrapped Dictionary
  failure, then the first offender raised at its member's VALUE offset in
  the combined field value), `valid?` the boolean mirror, and strict
  construction (byte-sequence values must be Strings tagged ASCII-8BIT,
  preference values Integers 0..10, keys Structured Fields keys) with
  canonical `to_s`, class-checked equality and the reader set (`[]` answering
  the bare bytes so `parsed["sha-256"] == Digest::SHA256.digest(body)` holds
  bytewise).
- The content-versus-representation distinction in the types (the RFC 3230
  lesson of §1.3 and Appendix E): `ContentDigest.of` hashes content,
  `ReprDigest.of` hashes representation data, and a ContentDigest never
  equals a ReprDigest; the preference fields carry no compute helper
  (§4's preferences are a hint, the selection policy is the caller's).
- Registry: `Fast::Digest::ALGORITHMS` — RFC 9530 §7.2 Table 2's eight
  entries as frozen data (sha-512 and sha-256 Active, the other six
  Deprecated, descriptions verbatim), with `registered?`/`status`/`active?`/
  `deprecated?`/`computable?` lookups and unknown-key passthrough.
- Compute: `Fast::Digest.compute` — exactly the stdlib `Digest::SHA256`/
  `SHA512`/`MD5`/`SHA1` bytes as frozen ASCII-8BIT Strings, hashed bytewise
  whatever the input encoding; the four checksum entries (unixsum,
  unixcksum, adler, crc32c) and unknown keys raise `Fast::Digest::Error`
  naming the key — carried bytewise through the fields, never computed or
  verified locally.
- Trailer support: the String-or-Array-of-lines entry points (RFC 9651
  §4.2 combining, duplicates last-wins) plus the §6.4/§6.3 cautions in the
  README (intermediaries may drop trailers; combining mangles what a
  signature covers).
- Budgets: the allocation tests for the eight paths (integrity parse,
  fail-closed, preference parse, emit, compute, `.of`, strict parse,
  `valid?`), measured and frozen in the file's comment.
- Scaffold: the gemspec (one runtime dependency, fast-sfv), the README
  front door, and this changelog. The documentation pass and this 0.1.0
  release land together (docs are part of the product — the family's
  release rule).
- Docs: the diátaxis docs tree under `docs/` (tutorial, four how-to
  guides, two reference pages, four explanations), the README front door
  with the documentation index, and the both-mode performance page from
  one measurement session (interpreter and YJIT side by side, the
  benchmark kit alongside). Every fenced ruby example was executed as
  printed and every RFC citation checked against the RFC text by the
  pipeline's independent review. The gemspec metadata completes with
  `documentation_uri` pointing at the docs tree.
