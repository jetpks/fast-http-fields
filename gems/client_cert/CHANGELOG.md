# Changelog

## 0.1.1 (2026-11-27)

- Fixed: the strict `parse!` positions member errors through the
  substrate's region scan (`Fast::SFV.regions_list`, fast-sfv 0.2.0)
  instead of this gem's private walk — the private walk desynced on a
  legal RFC 9651 shape (a display string whose content ends in a
  backslash — §4.2.10 has no backslash escaping, backslash is literal
  content and only DQUOTE closes) carried as a chain member's
  parameter, so a later member's error pointed past the field's end.
  Every pinned offset is unchanged; the private walk class and the
  local field-line join are gone (the substrate's validated combine
  is the only one).
- Fixed: the empty Byte Sequence `::` is refused at the shared
  Checks seam — a DER-encoded X.509 certificate is never zero bytes
  (§2.1), so `Cert.parse` answers nil (the field treated as absent,
  the unauthenticated connection), `Chain.parse` answers the shared
  empty value, `valid?` answers false, the strict parses raise
  positioned at the member, and both constructions raise
  SerializeError — one seam, every boundary.
- Fixed: `field_to_pems` splits on the substrate's parameter-aware
  member boundaries instead of every comma — a comma inside a quoted
  parameter value is content, never a separator, so a param-carrying
  member converts whole to its PEM block and an error names a real
  member's value, never a split artifact. A field value that is not
  a Structured Fields List raises the base Error carrying the scan's
  message.
- Hygiene: the gemspec comment rewritten self-contained; the
  fast-sfv dependency floored at `~> 0.2` (the region-scan API this
  release reads).

## 0.1.0 (2026-11-26)

- Fields: `Fast::ClientCert::Cert` and `Fast::ClientCert::Chain` — the
  two RFC 9440 request fields as frozen value objects over fast-sfv,
  with the family mechanics: `parse` fail-closed (a malformed field,
  or any member violating the field's Byte Sequence constraint, is the
  entire field ignored per RFC 9651 §2.2 — Cert answers nil, "no
  certificate, the unauthenticated connection"; Chain answers the
  shared frozen empty value, the same answer an absent field gives; no
  member-level filtering), `parse!` positioned strict truth (the
  wrapped Item/List failure, then the constraint — Cert at the value's
  first non-OWS byte, Chain at the first offending member's, through
  the quote-aware positioning Scan that runs only on the error path),
  `valid?` the boolean mirror, and strict construction with canonical
  `to_s`, class-checked equality and the reader sets (`der`; `ders`,
  `size`, `empty?`, `each` Enumerator-graceful without a block, `[]`,
  `split`).
- The singleton rule rides the Item grammar (§2.2: Client-Cert "MUST
  NOT have a list of values or occur multiple times in a request" —
  the Item parse fails a second member by itself, no detection code);
  split lines recombine per RFC 9651 §4.2 into the same failure, and
  `split` cuts a held chain back into per-instance lines for §2.3's
  MAY-split (§3.1's header compression note).
- PEM helpers: `pem_to_field`, `field_to_pem`, `pems_to_field` and
  `field_to_pems` — the §2.1 string surgery both directions ("it will
  be sufficient to replace ---(BEGIN|END) CERTIFICATE--- with ':' and
  remove line breaks in order to generate an appropriate item"), the
  inverse wrapped at 64 characters per line (RFC 7468's form), pure
  Ruby — no OpenSSL, DER bytes opaque. The PEM side trusts the armor
  and never validates base64 (a mangled payload fails the Structured
  Fields parse downstream, fail-closed); the field-value side is
  strict. Usage failures raise the base `Fast::ClientCert::Error`;
  wrong input types raise TypeError.
- Errors: `Fast::ClientCert::Error` → `ParseError`/`SerializeError`,
  both carrying `#offset` — the family shape; one rescue guards the
  whole gem.
- Budgets: the allocation tests for the nineteen paths (the two
  fields' parse/parse!/valid?/new/emit paths, the split-lines parse,
  the fail paths, the split, and the four PEM helpers), measured and
  frozen in the file's comment.
- Scaffold: the gemspec (one runtime dependency, fast-sfv), the README
  front door, and this changelog. The documentation pass and this
  0.1.0 release land together (docs are part of the product — the
  family's release rule).
- Docs: the diátaxis docs tree under `docs/` (tutorial, three how-to
  guides — the TTRP insertion with the sanitization rules, the origin
  validation with OpenSSL on the caller's side, the PEM round-trips —
  one reference page, four explanations), the README front door with
  the quickstart and the documentation index, and the both-mode
  performance page from one measurement session (interpreter and
  YJIT side by side, the benchmark kit alongside, rubocop-clean).
  Every fenced ruby example was executed as printed and every RFC
  citation checked against the RFC text by the pipeline's independent
  review.
