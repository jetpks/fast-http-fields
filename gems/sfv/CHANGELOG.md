# Changelog

## 0.2.0 (2026-11-26)

- Fixed: non-ASCII-compatible field input no longer escapes the error
  contracts as `NoMethodError` or `Encoding::CompatibilityError`. A
  UTF-16/UTF-32 String, and an Array line whose encoding cannot join
  with the others, are rejected as a positioned
  `Fast::SFV::ParseError` — never transcoded: the family rejects
  rather than converts, and a real h1/h2/h3 stack never hands you
  UTF-16. An ASCII-compatible line that merely carries a high byte
  keeps its byte-exact behavior (the ASCII failure at its exact
  byte), and the plain all-ASCII join allocates nothing.
- Added: the region scan — `Fast::SFV.regions_item`,
  `Fast::SFV.regions_list` and `Fast::SFV.regions_dict`, answering a
  frozen `Fast::SFV::Regions`: the combined field value itself plus
  one frozen `Fast::SFV::Region` per member, carrying the key's and
  the value's byte offsets and the parameter group that follows (the
  valueless Boolean-true member's included — RFC 9651 §4.2.2 step 3
  parses parameters on it). The scan walks the Parser's own §4.2
  grammar — the same byte classes, the same steps, the same
  strictness — so a caller can slice member values and position its
  own diagnostics without re-walking the grammar; the field gems'
  strict walks adopt it in their next releases. Strictly additive:
  no existing entry point changed.
- Fixed: the substrate's tests now pin exact error offsets — the
  display-string-backslash and valueless-member-with-parameters
  trigger shapes (`foo=%"\"`, `a;q=1, b=11, a=3`) and the strict-walk
  repro set, as the region scan's span pins, plus the parse/scan
  message-and-offset agreement on malformed content. The README's
  `offset # => 4` example executes as a spec again (the docs-example
  spec was lost in 0.1.1's docs regeneration without a changelog
  note) — `test/fast/sfv/docs.rb` is back, executing the README and
  how-to-guide examples as printed.
- Docs: the parse how-to states the field-line encoding policy
  (rejected, never transcoded) with its example executed by the
  docs-example spec.

## 0.1.1 (2026-11-25)

- Docs: re-authored from scratch — the README front door and the
  diataxis tree under `docs/` (tutorial, four how-to guides, two
  reference pages, three explanations). Every ruby example executed
  as printed, every RFC 9651 section citation checked against the RFC
  text, and the performance page carries both runtime modes side by
  side: the plain interpreter and YJIT (the compiling runtime, the
  common production configuration).
- Internals: an idiomaticity pass over the parse and emit paths —
  binary-string literals (`"".b`), `String#ascii_only?` as the ASCII
  pre-scan's hot path (the offset walk kept for the error it
  reports), `case` member dispatch, and the long methods decomposed
  into named phases (`emit_decimal`'s scan, rounding and wire-digit
  emission; `parse_number`'s limits; the display-string walks).
  Behavior is byte-identical: every error message and offset, every
  parse and serialize allocation budget unchanged. Parse throughput
  improved with the `ascii_only?` scan (interpreter `parse_item`
  256k → 343k i/s on the benchmark samples; YJIT 1.67M → 2.07M).
- The repo's comments no longer reference internal
  development-workspace documents.

## 0.1.0 (2026-11-25)

- Tokens: token values switched from `Symbol` to frozen
  `Fast::SFV::Token < String` — the class is the wire-type tag, the
  content is String semantics (`==`, `eql?`, `hash` and `to_s`
  inherited; `inspect` overridden to name the class), and construction
  validates the full token grammar (RFC 9651 §3.3.4) at the boundary
  (`ArgumentError` for invalid content, `TypeError` for a non-String,
  no length cap). The serializer dispatches on the class: a `Token`
  emits bare, a plain `String` quoted, an ASCII-8BIT `String` still a
  byte sequence, and a `Symbol` — wrong-typed input after the switch —
  raises positioned `SerializeError`. Parse and serialize allocation
  budgets re-measured and re-frozen for the Token path (a token value
  costs its content slice plus the `Token`; no intern cache — measured
  +1 object per value worst-case, not needed). A deliberate, documented
  divergence from starry, which returns `Symbol` tokens.
- Serializer: `Fast::SFV.serialize_item`/`serialize_list`/
  `serialize_dict` and `to_s` on the value objects — the strict RFC
  9651 §4.1 emit (all eight bare item types, parameters, inner lists,
  dictionaries, the Boolean-true short forms, the empty-container field
  omission), append-only byte emission with the Ruby type as the
  wire-type tag (no coercion, no content inference), the positioned
  `Fast::SFV::SerializeError`, and the vendored httpwg corpus's
  serialize side (553 serialisation-tests records plus 734 parse-side
  round trips) refereeing every emit edge, with the decimal digits
  rounded as written and ties to even. The emit allocation budgets (the
  output String only) join the parse budgets, and the benchmark bundle
  (`gems.rb` + `benchmark/sfv.rb`) compares against starry, the RFC
  8941 reference implementation, on the common surface — a reference
  comparison, never a runtime dependency.
- Parser: `Fast::SFV.parse_item`/`parse_list`/`parse_dict` with the
  `valid_item?`/`valid_list?`/`valid_dict?` mirrors — the strict RFC 9651
  §4.2 grammar (all eight bare item types, parameters, inner lists,
  dictionaries, the `", "` field-line combining), the frozen value
  objects (`Item`, `InnerList`, `Date`, `DisplayString`), the positioned
  `Fast::SFV::ParseError`, and the vendored httpwg conformance corpus
  (1607 records) refereeing every grammar edge.
- Scaffold: `Fast::SFV` module and version, the monorepo test harness
  (`config/sus.rb` routing `gems/*/lib` + `gems/*/test`), the gemspec,
  and the packaging machinery (CI build loop, release dispatch map,
  `script/verify-packaged.rb`).
- Docs: the diátaxis docs tree under `docs/` (tutorial, four how-to
  guides, two reference pages, three explanations), the README
  quickstart with the documentation index, the docs-examples spec
  (`test/fast/sfv/docs.rb`) that executes every fenced example and
  checks every documented output, and the completed gemspec metadata
  (`documentation_uri` pointing at the docs tree).
