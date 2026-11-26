# Performance and allocation budgets

## Design goals

The hot paths ride the family substrate: every field operation is one RFC 9651 Dictionary parse through fast-sfv, so this gem's discipline is to add as little as possible on top — the strict parse's positioning scan, the frozen value object, the shared empty structures, one output String per emission (`lib/fast/digest/fields.rb:36-47,243-247`; `test/fast/digest/allocations.rb:1-29`).

## How the paths stay cheap

- The lenient parse is the strict parse rescued — one walk answers both, never two parses (`lib/fast/digest/fields.rb:172-176`; `test/fast/digest/allocations.rb:86-91`).
- The fail-closed fall allocates the empty value's own two objects (the frozen Hash is shared, `lib/fast/digest/fields.rb:31-34`).
- The value object is `allocate` + `hold` on the parse path — no re-validation, no member copy (the parsed frozen Hash IS the members Hash) (`lib/fast/digest/fields.rb:240-247,343-347`).
- `to_s` serializes into the one output String fast-sfv builds, `""` when nothing is held (`lib/fast/digest/fields.rb:307-316`; `test/fast/digest/allocations.rb:63-68`).
- The compute helpers answer the stdlib's own bytes — nothing re-implemented, nothing cached (`lib/fast/digest/registry.rb:100-110`).

## The benchmark

Measured in both runtime modes — the plain interpreter (the no-JIT floor) and YJIT (the compiling runtime, the common production configuration):

```sh
BUNDLE_GEMFILE=gems/digest/gems.rb bundle exec ruby gems/digest/benchmark/digest.rb
BUNDLE_GEMFILE=gems/digest/gems.rb bundle exec ruby --yjit gems/digest/benchmark/digest.rb
```

Full mode: 5 s timed + 1 s warmup per operation, both modes from one measurement session. Pins benchmark-ips 2.15.1.

No other Ruby implementation of RFC 9530 exists — starry, the family's reference comparator for fast-sfv, implements the Structured Fields substrate, not these fields — so there is no comparator row; the numbers hold fast-digest to its own budgets (the objects/call column is the discipline the tests freeze, computed on the same inputs as the budget tests); i/s is indicative.

Interpreter mode:

```
ruby 4.0.10 (2026-11-19 revision a704b7cd95) +PRISM [arm64-darwin25]; fast-digest 0.1.0
the numbers hold fast-digest to its own budgets (the objects/call column); i/s is indicative
```

| operation | i/s | ±% | objects/call |
|---|---|---|---|
| ContentDigest.parse | 84,623 | 0.13 | 10.00 |
| ReprDigest.parse | 84,629 | 0.14 | 10.00 |
| ReprDigest.parse (malformed) | 680,371 | 0.67 | 9.00 |
| WantContentDigest.parse | 158,067 | 0.19 | 15.00 |
| WantReprDigest.parse | 158,274 | 0.98 | 15.00 |
| ReprDigest#to_s | 352,906 | 0.40 | 1.00 |
| WantReprDigest#to_s | 281,117 | 0.41 | 1.00 |
| Fast::Digest.compute | 2,956,121 | 0.45 | 2.00 |
| ReprDigest.of | 903,819 | 0.23 | 8.00 |
| ReprDigest.parse! | 84,950 | 1.03 | 10.00 |
| WantReprDigest.valid? | 157,657 | 0.16 | 15.00 |

YJIT mode:

```
ruby 4.0.10 (2026-11-19 revision a704b7cd95) +YJIT +PRISM [arm64-darwin25]; fast-digest 0.1.0
the numbers hold fast-digest to its own budgets (the objects/call column); i/s is indicative
```

| operation | i/s | ±% | objects/call |
|---|---|---|---|
| ContentDigest.parse | 591,608 | 0.95 | 10.00 |
| ReprDigest.parse | 593,551 | 1.23 | 10.00 |
| ReprDigest.parse (malformed) | 978,699 | 1.28 | 10.00 |
| WantContentDigest.parse | 640,352 | 0.55 | 15.00 |
| WantReprDigest.parse | 686,968 | 0.96 | 15.00 |
| ReprDigest#to_s | 2,084,923 | 1.63 | 1.00 |
| WantReprDigest#to_s | 883,616 | 0.99 | 1.00 |
| Fast::Digest.compute | 3,626,911 | 1.59 | 2.00 |
| ReprDigest.of | 1,890,443 | 1.67 | 8.00 |
| ReprDigest.parse! | 591,954 | 1.08 | 10.00 |
| WantReprDigest.valid? | 691,683 | 1.05 | 15.00 |

Reading the two tables: objects/call is mode-independent on ten of the eleven rows; the malformed-parse row measures one object more under YJIT than under the interpreter (10 vs 9) — the raised-and-rescued Dictionary failure measures differently under the compiled runtime (the same class of exception fast-priority's perf page documents); the budgets are frozen under the interpreter, the mode the test suite runs in, and hold there.

Benchmark samples: the integrity parses on the B.1 value `"sha-256=:RK/0qy18MlBSVnWgjwz6lZEWjP/lF5HF9bvEF8FabDg=:"`, the malformed fall on `"!!"`, the preference parses on `"sha-512=3, sha-256=10, unixsum=0"`, `to_s` on the parsed B.1 and the parsed preference values, compute and `.of` on `"the bytes to hash"`, `parse!`/`valid?` on the B.1 and preference values — the same inputs as the budget tests (the three sibling-field rows — ContentDigest.parse, WantContentDigest.parse, WantReprDigest#to_s — run their twins' inputs; they share the Field machinery and answer alike by construction).

Caveats:

- benchmark-ips timings vary run to run (the ±% column) and across machines — the i/s column is indicative, not contractual.
- objects/call is deterministic: one settled call's object count with GC disabled over a 10,000-call batch — it is the column the gem holds itself to.
- The ruby/platform banner above each table names the measured environment; both modes ran on the same machine and ruby build in one session.

## The allocation budgets

Budgets are frozen in `test/fast/digest/allocations.rb` (measured on Ruby 4.0.10) — a regression the tests catch.

| operation | input | bound | measured |
|---|---|---|---|
| integrity parse | `"sha-256=:RK/0qy18MlBSVnWgjwz6lZEWjP/lF5HF9bvEF8FabDg=:"` | < 11 | 10 — the Fast::SFV Parser, the dictionary Hash with its key String and Item, the Scan with its offsets Hash and key slice, and the frozen value object with its keys view |
| parse (malformed fall) | `"!!"` | < 10 | 9 — the SFV parse's failure path (the error with its message), the wrapped ParseError, and the empty value object with its keys view |
| preference parse | `"sha-512=3, sha-256=10, unixsum=0"` | < 16 | 15 — the Parser, the dictionary with three keys and three Items, the Scan's offsets Hash with three key slices, the value object and its keys view |
| emit | the parsed B.1 value | < 2 | 1 — the output String only, whatever the member count |
| compute | `("sha-256", "the bytes to hash")` | < 3 | 2 — the stdlib's digest String and its one internal object |
| `.of` compute-and-construct | `("sha-256", "the bytes to hash")` | < 9 | 8 — the compute 2, then construction's six: the two Hashes a literal member argument costs, the Item, the value object and its keys view |
| strict parse | the B.1 value | < 11 | 10 — the parse path's own count (the lenient parse is this path rescued) |
| `valid?` | `"sha-512=3, sha-256=10, unixsum=0"` | < 16 | 15 — the preference parse's own count (the mirror adds nothing) |

The benchmark table's objects/call column and these budgets are the same discipline on the same inputs (the interpreter column matches each budget's measured count; the sibling-field rows — ContentDigest.parse, WantContentDigest.parse, WantReprDigest#to_s — share the machinery and answer alike).

## How to reproduce

Benchmark:

```sh
BUNDLE_GEMFILE=gems/digest/gems.rb bundle install
BUNDLE_GEMFILE=gems/digest/gems.rb bundle exec ruby gems/digest/benchmark/digest.rb
BUNDLE_GEMFILE=gems/digest/gems.rb bundle exec ruby --yjit gems/digest/benchmark/digest.rb
```

Quick mode for sanity-check (0.5 s time / 0.2 s warmup, not for publishing):

```sh
BENCH_QUICK=1 BUNDLE_GEMFILE=gems/digest/gems.rb bundle exec ruby gems/digest/benchmark/digest.rb
```

Allocation measurement: `GC.stat(:total_allocated_objects)` deltas averaged over runs, everything a measured block touches a local; GC disabled over a 10,000-call batch.

Caveats: benchmark-ips timings vary run to run and across machines; objects/call is deterministic per ruby; the measured environment is named by the ruby banner; both modes ran on the same machine and ruby build in one session.
