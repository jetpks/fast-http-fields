# Changelog

## 0.1.1 (2026-11-27)

- Fixed: the strict `parse!` positions §4 semantic errors through the
  substrate's region scan (`Fast::SFV.regions_dict`, fast-sfv 0.2.0)
  instead of this gem's private walk — the private walk desynced on
  two legal RFC 9651 shapes (a display string whose content ends in a
  backslash — §4.2.10 has no backslash escaping, backslash is literal
  content and only DQUOTE closes — and parameters on the valueless
  member, `a;q=1`), so `x=%"\", u=9` and `a;b=1, u=9` raised with a
  nil offset where the member's value sits. Every pinned offset is
  unchanged; the private walk class and the local field-line join
  are gone (the substrate's validated combine is the only one), and
  the clean strict path no longer allocates the walk's offsets.
- Fixed: `Parameters#to_s` (and both frame encoders through it)
  rewraps a substrate `SerializeError` as
  `Fast::Priority::SerializeError` with its message and offset —
  every failure this gem raises descends from
  `Fast::Priority::Error`, the one-rescue guarantee the README
  states.
- Fixed: `H2.encode_payload` rejects a prioritized stream ID of 0 —
  RFC 9218 §7.1 makes a received 0x0 an unconditional connection
  error of type PROTOCOL_ERROR, so a strict sender never emits one
  (the bound is 1..0x7FFFFFFF; the receiver's stream-state rules
  remain the caller's).
- Hygiene: the h3 comment's varint arithmetic corrected (0xF0700 =
  984832, a 4-byte form spelled `80 0f 07 00`); the gemspec comment
  rewritten self-contained; the fast-sfv dependency floored at
  `~> 0.2` (the region-scan API this release reads).

## 0.1.0 (2026-11-26)

- Field: `Fast::Priority.parse` / `parse!` / `valid?` — the RFC 9218 §4
  recipient semantics over the Priority header field, an RFC 9651
  Dictionary consumed through fast-sfv: the whole-field malformed and
  absent cases answer the §4 defaults (urgency 3, incremental false,
  no member held), the member-level MUST-ignore filter drops
  out-of-range and wrong-typed `u`/`i` while unknown parameters pass
  through as parsed, the strict parse wraps the Dictionary failure
  with its message and byte offset and points §4 semantic errors at
  the effective member's value, and `valid?` mirrors it with a
  boolean.
- Value object: `Fast::Priority::Parameters` — the frozen holder of
  the effective members with `urgency`/`incremental`/`unknown`/
  `members` readers, the canonical `to_s`, member-absence semantics,
  construction validation, canonical-wire-form equality, and the §8
  merge helper (each known parameter the other holds wins, its
  omissions keep self's).
- Frames: `Fast::Priority::H2` and `Fast::Priority::H3` — the §7.1 and
  §7.2 PRIORITY_UPDATE payload codecs, byte-exact in both directions
  (the Reserved bit masked on h2 receipt, the RFC 9000 §16 minimal
  varint on h3 encode and the Appendix A.1 algorithm on decode, any
  form), with the §7 field-value parse failure surfaced on the decode
  result for the caller's connection-error MAY.
- Interop: the gem's own bundle (`gems.rb`) wires protocol-http2 0.29.2
  as a test-group peer staging offline from the gitignored root cache,
  exercising both directions against their framing stack (the h3 side
  has no usable Ruby peer — the ecosystem's HTTP/3 gems are native
  extensions without a frame API — so it is verified against the RFC
  vectors alone).
- Scaffold: the gemspec (one runtime dependency, fast-sfv), the
  README front door, the allocation budgets for the eight paths, and
  this changelog. The documentation pass and this 0.1.0 release land
  together (docs are part of the product — the family's release rule).
- Docs: the diátaxis docs tree under `docs/` (tutorial, four how-to
  guides, two reference pages, three explanations), the README front
  door with the documentation index, and the both-mode performance page
  from one measurement session (interpreter and YJIT side by side, the
  benchmark kit alongside). Every fenced ruby example was executed as
  printed and every RFC citation checked against the RFC text by the
  pipeline's independent review. The gemspec metadata completes with
  `documentation_uri` pointing at the docs tree.
