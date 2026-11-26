# Changelog

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
