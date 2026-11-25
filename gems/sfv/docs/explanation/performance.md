# Performance and allocations

## How these numbers were measured

The table below was produced by the benchmark in
`gems/sfv/benchmark/sfv.rb`, run from the repo root through the
benchmark bundle (`gems/sfv/gems.rb`, separate from the test bundle)
with its comparator gems staged offline from the gitignored
`gems/sfv/vendor/cache`:

```sh
BUNDLE_GEMFILE=gems/sfv/gems.rb bundle install --local
BUNDLE_GEMFILE=gems/sfv/gems.rb bundle exec ruby gems/sfv/benchmark/sfv.rb
```

Ruby version from the run's first output line:

```text
ruby 4.0.10 (2026-11-19 revision a704b7cd95) +PRISM [arm64-darwin25]; fast-sfv 0.1.0; starry 0.2.0
```

- Gem floor Ruby `>= 3.4` (`fast-sfv.gemspec`), CI matrix 3.4 / 4.0,
  test framework `sus`.
- `benchmark-ips` 2.15.1 (`gems/sfv/gems.locked`).
- Full mode: 5 s measure / 1 s warmup per operation
  (`gems/sfv/benchmark/sfv.rb`). Quick mode (`BENCH_QUICK=1`) is
  0.5 s measure / 0.2 s warmup and is not used for published numbers.
- `starry` 0.2.0 is the RFC 8941 reference implementation the
  benchmark compares against — a dev-only comparator, never a
  runtime dependency. The compared surface is the RFC 8941 subset
  both libraries implement (see
  [RFC 9651 vs RFC 8941](rfc-9651-vs-8941.md)).
- Objects per call is measured with GC disabled over 10,000 settled
  calls: one warm call, `GC.start`, `GC.disable`, the delta of
  `GC.stat(:total_allocated_objects)` over the batch, `GC.enable` in
  `ensure`. GC-disabled counting measures allocation, not retention.
- Results vary run-to-run (see the `±%` column, which is
  `benchmark-ips`' own error estimate) and machine-to-machine. The
  table is an observation, not a guarantee.

## Throughput

```text
ruby 4.0.10 (2026-11-19 revision a704b7cd95) +PRISM [arm64-darwin25]; fast-sfv 0.1.0; starry 0.2.0
starry is the RFC 8941 reference implementation: a reference comparison, not a ranking.
| operation | i/s | ±% | objects/call |
|---|---|---|---|
| Fast::SFV.parse_item | 254,693 | 0.66 | 5.00 |
| Starry.parse_item | 371,997 | 0.71 | 26.00 |
| Fast::SFV.parse_list | 195,197 | 0.59 | 14.00 |
| Starry.parse_list | 128,535 | 0.92 | 81.00 |
| Fast::SFV.parse_dict | 204,464 | 0.83 | 15.00 |
| Starry.parse_dictionary | 131,913 | 0.86 | 74.00 |
| Fast::SFV.serialize_item | 379,203 | 0.91 | 1.00 |
| Starry.serialize (item) | 846,217 | 0.92 | 13.00 |
| Fast::SFV.serialize_list | 302,510 | 0.81 | 1.00 |
| Starry.serialize (list) | 308,160 | 0.70 | 50.00 |
| Fast::SFV.serialize_dict | 285,992 | 0.89 | 1.00 |
| Starry.serialize (dictionary) | 264,026 | 0.68 | 49.00 |
```

Twelve rows, labels exactly as in the benchmark's operations hash:
the three Fast::SFV parse entry points against starry's, the three
Fast::SFV emit entry points against starry's single serialize on
starry's own parsed values. `i/s` is comma-grouped and rounded; `±%`
is the `benchmark-ips` error estimate; `objects/call` is the
GC-disabled allocation count above. What the table says is what it
says: starry is faster on `parse_item` and on serializing an item,
`serialize_list` sits inside the run-to-run error of the two rows'
`±%` columns, fast-sfv is faster on `parse_list`, `parse_dict` and
`serialize_dict`, and fast-sfv allocates fewer objects on every
operation. No derived speedup ratios are stated beyond the copied
table, and no ranking is implied — starry is the reference, credited
as such.

## Objects per call

The `objects/call` column above is the measured allocation cost of
the benchmark's own samples — an item with a string parameter, a
three-member list with an inner list, a mixed dictionary — which are
richer fields than the budget tests use. The budgets the gem is held
to are pinned by the suite, run as:

```sh
bundle exec sus gems/sfv/test/fast/sfv/allocations.rb
```

The frozen budgets, cited to `test/fast/sfv/allocations.rb` (measured
on Ruby 4.0.10, averaged over 100 runs per assertion):

- parse a bare item: 2
- parse a token bare item: 4
- parse an item with parameters: 8
- parse a string item: 3
- parse a byte sequence item: 3
- parse a display string item: 4
- parse a three-token list: 11
- parse a multi-line list: 5
- parse a mixed dictionary with an inner list: 11
- serialize a bare item: 1
- serialize an item with parameters: 1
- serialize a decimal item: 2
- serialize a list: 1
- serialize a dictionary: 1

The serialize budgets are the output String only, whatever the member
count: the emission appends into one buffer, spelling integers by
division and appending tokens, strings and keys whole, so a
100-member list is still 1. The one exception is a decimal item's 2 —
the `Float#to_s` text its digits are read from, the one unavoidable
temporary.

The budgets and the table's fourth column are distinct, by design:
the budgets are the floor the test suite pins on a fixed Ruby
version, the table is a live measurement on the running Ruby over
realistic fields. Counts are version-specific because
immediate-Integer and Flonum ranges differ across Ruby versions.

## Why it is cheap

- The parse walks the input by byte index with 256-entry character
  class tables — no regex per token, no scan pointer object; integers
  accumulate in place, strings are one contiguous slice.
- The emit appends bytes into one output String — the only object an
  emission allocates.
- Items with no parameters share one frozen empty Hash; nothing can
  mutate a frozen Hash, so sharing is free.

The scanner discipline and the ruling behind each of those shapes is
in [Design decisions in fast-sfv](design-decisions.md).

## Correctness context

Throughput is not the whole story: the same suite runs the vendored
httpwg conformance corpus under `test/corpus/` — 1607 parse records,
553 serialisation-tests records and 734 parse-side round trips — so
every grammar edge the corpus knows is pinned by a test. The
benchmark samples are ordinary fields by comparison.

## Where to go next

- [Design decisions in fast-sfv](design-decisions.md) — the scanner
  and allocation discipline behind the budgets.
- [Type mapping — RFC 9651 to Ruby](../reference/type-mapping.md) —
  the values whose construction the budgets count.
- [RFC 9651 vs RFC 8941](rfc-9651-vs-8941.md) — why the compared
  surface is the 8941 subset.
