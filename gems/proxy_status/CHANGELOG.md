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
- Fields: `Fast::CacheStatus` — the RFC 9211 Cache-Status field on the
  same List engine: a List of parameterized members, one per cache
  that handled the request, the first closest to the origin server,
  with the eight §2.1-§2.8 parameters as typed readers on the `Cache`
  member value object (hit, fwd, fwd-status, ttl, stored, collapsed,
  key, detail — false is a value, never an absence), `hit_and_fwd?`
  surfacing §2.1's exclusivity SHOULD without ever gating anything,
  §2.2's fwd value set pinned as frozen data
  (`Fast::CacheStatus::FWD`) and validated at construction only
  (an unregistered Token parses and round-trips untouched), the
  parameters table pinned as frozen data
  (`Fast::CacheStatus::PARAMETERS`), and `append` (§2's
  append-yourself — this cache's member appended as the LAST, a new
  frozen value).
- Fields: `Fast::TargetedCacheControl` — the RFC 9213 targeted
  cache-control fields as a Dictionary value object (the RFC 9530
  digest shape): §2.1's type-inference rules read on parse (valueless
  → Boolean true, quoted → String, token → Token/Integer/Decimal by
  content) and enforced on emit ("Implementations MUST NOT generate
  values that violate these inferred constraints"), the five
  §2.2 MUST-implement directives pinned as frozen data
  (`Fast::TargetedCacheControl::DIRECTIVES`) with unknown directives
  passing through, `FIELD_NAME` ("CDN-Cache-Control", the registered
  instance, and no "-Cache-Control" suffix matcher — §2.4's MUST NOT),
  and the leniency split: an empty or malformed field is ignored
  entirely (§2.1's MUST) while a violating directive is
  preserved-but-flagged — `#violating` answers the SHOULD-NOT-consume
  set, the value stays in the data and round-trips.
- Engine: `Fast::ProxyStatus::ListField` — the List-of-members
  machinery the two List fields share, extracted from Proxy-Status
  behavior-invisibly (every offset pin, allocation ceiling and test
  of the first half held exactly): the class-level one-walk/
  two-policy parse machinery, the instance surface over the members
  ivar, the positioning `Scan`, and the `Member` base the two member
  classes build on. The RFC 9213 field is a Dictionary and does not
  ride it.
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
- Budgets: the allocation tests for the ten Proxy-Status paths
  (parse, the malformed fall, the member-violation fall, strict
  parse, `valid?`, Hop construction, append on a held value, append
  over a received String, promote, emit), extended with the ten
  Cache-Status paths and the seven TargetedCacheControl paths
  (including the flagged parse — the leniency split's own price),
  measured and frozen in the file's comment.
- Scaffold: the gemspec (one runtime dependency, fast-sfv), the README
  front door, and this changelog. The documentation pass and the 0.1.0
  release land with the next entry of the gem map (the docs tree over
  all three modules) — docs are part of the product, the family's
  release rule.
