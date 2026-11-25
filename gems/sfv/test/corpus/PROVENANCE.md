# Provenance

Vendored from <https://github.com/httpwg/structured-field-tests> at
commit `4a4782f8234512af133f6f57c4ca998578b57110`
("Merge pull request #131 from apasel422/base32", 2025-11-25 UTC
clone, `git clone https://github.com/httpwg/structured-field-tests`).

Contents: every `*.json` of that repository — the 20 parse-side test
files at the root, all four files under `serialisation-tests/`
(serialization is gated by a later iteration, not the parser), and all
four files under `schema/` — plus `LICENSE.md` (the corpus's own
license, retained per its redistribution terms) and `README.md` (the
test-record semantics: `raw`, `header_type`, `expected` with `__type`
objects, `must_fail`, `can_fail`, `canonical`; decimals compare
as-written).

Not vendored: `generate.py`, `.editorconfig`, `.github/` (upstream
regeneration machinery — refresh the whole tree from upstream if the
corpus ever needs updating). Never edit these files in place.

Provenance note (frozen 2026-11-25, iteration `sfv-parser`): the
sha256 of every file here is pinned in that iteration's Grounds and
enforced by its `corpus-digests` gate.
