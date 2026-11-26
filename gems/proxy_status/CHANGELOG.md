# Changelog

## 0.1.0 (2026-11-26)

- Fields: `Fast::ProxyStatus` — the RFC 9209 Proxy-Status field as a
  frozen value object over fast-sfv: a List of parameterized members,
  one per intermediary that handled the response, the first closest to
  the origin server, with the family mechanics — `parse` with the
  diagnostic leniency (a malformed field, or any member that is not a
  String or Token, is the entire field ignored per RFC 9651 §2.2, the
  shared frozen empty value; unknown and wrong-typed §2.1 parameters
  preserved in the data and ignored semantically, so §2.1.5's own
  quoted-string error example parses), `parse!` positioned strict truth
  (the wrapped List failure, then the member and §2.1 parameter
  constraints, the first offender in List order raised at the
  offending value's byte offset), `valid?` the boolean mirror, strict
  construction, canonical `to_s`, class-checked equality.
- `Fast::ProxyStatus::Hop` — the member value object, an
  `Fast::SFV::Item` subclass: the raw `#[]` and `#params` beside the
  five §2.1 typed readers (`error`, `next-hop`, `next-protocol`,
  `received-status`, `details`), the strict construction boundary (the
  identifier a plain String or a Token — the class is the wire-type
  tag; the five §2.1 parameters type-checked; unknown parameters any
  bare Structured Fields type; value and params frozen in place), and
  the shared constraint surface the parse walk and the construction
  read.
- Operations: `append` (§2's append-yourself — the upstream value
  parsed leniently, this intermediary's member appended as the LAST,
  a new frozen value) and `promote` (§2's trailer-promotion algorithm
  spec-exact — the leftmost match by value characters across the
  String and Token forms, replacement in its entirety, consumed
  trailer members, the trailer removed when nothing remains —
  answering a frozen `Fast::ProxyStatus::Promotion`).
- Registry: `Fast::ProxyStatus::ERRORS` — §2.3's 32 proxy error types
  as frozen data in document order (recommended statuses, response-only
  flags, extra parameters; the two prose statuses verbatim), with
  `registered?`/`recommended_status`/`response_only?`/
  `extra_parameters` lookups and unknown passthrough; the registry
  never gates a parse or an emit.
- Budgets: the allocation tests for the ten paths (parse, the
  malformed fall, the member-violation fall, strict parse, `valid?`,
  Hop construction, append on a held value, append over a received
  String, promote, emit), measured and frozen in the file's comment.
- Scaffold: the gemspec (one runtime dependency, fast-sfv), the README
  front door, and this changelog. The documentation pass and the 0.1.0
  release land with the next entry of the gem map (Cache-Status and
  Targeted Cache Control, RFC 9211/9213) — docs are part of the
  product, the family's release rule.
