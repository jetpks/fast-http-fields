# Changelog

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
