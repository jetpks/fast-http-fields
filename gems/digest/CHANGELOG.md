# Changelog

## 0.1.2 (2026-11-27)

- Fixed: the construction and parse boundaries never send a message
  into the value they are checking — a field's members Hash, each
  member's key (the Algorithm Key grammar) and value, and the strict
  `parse!`'s first-offender report read the value with the
  never-dispatch forms (`case value when Klass`, `Module#===`), so a
  classless value (a `BasicObject` descendant) at a boundary raises
  the documented `SerializeError` — or the parse-side `ParseError` —
  instead of escaping the error contract as a raw `NoMethodError`.
  The message names the value's class — or the placeholder "a
  classless object" — never the value's own `inspect` or another
  method it answers.
- Fixed: requirement messages lead with the requirement — "members
  must be a Hash, received …", "<key>: <rule>, received …" — so no
  message reads as if the received value were the required one.

## 0.1.1 (2026-11-27)

- Fixed: the strict `parse!` positions member errors through the
  substrate's region scan (`Fast::SFV.regions_dict`, fast-sfv 0.2.0)
  instead of this gem's private walk — the private walk desynced on
  two legal RFC 9651 shapes (a display string whose content ends in a
  backslash — §4.2.10 has no backslash escaping, backslash is literal
  content and only DQUOTE closes — and parameters on the valueless
  member, `a;q=1`), so a member after either raised at the wrong
  offset, named the wrong member, or carried a nil offset where an
  Integer is documented. The first offender is now chosen in the
  combined field value's member order (the effective, last-wins
  occurrence of each key, earliest in the value first) and positioned
  at its own value; every pinned offset is unchanged. The private
  walk class and the local field-line join are gone (the substrate's
  validated combine is the only one — an Array of lines joins once,
  not twice), and the clean strict path no longer allocates the walk's
  offsets (the Integrity parse drops from 10 to 7 objects, the
  three-member preference parse from 15 to 10; budgets re-pinned).
- Added: `#each` without a block answers an `Enumerator` over the same
  key/value pairs — the family's iteration convention; the allocation
  lands only on that cold path.
- Hygiene: the fast-sfv dependency floored at `~> 0.2` (the
  region-scan API this release reads).

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
