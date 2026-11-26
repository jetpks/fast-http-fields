# Changelog

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
