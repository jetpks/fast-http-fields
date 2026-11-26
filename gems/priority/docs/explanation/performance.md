# Performance and allocation budgets

## Design goals

The hot paths ride the family substrate: every field operation is one RFC 9651 Dictionary parse through fast-sfv, so this gem's discipline is to add as little as possible on top — the frozen value object, the shared empty structures, one output String per emission (`lib/fast/priority/parameters.rb:15-21`; `test/fast/priority/allocations.rb:1-20`).

## How the paths stay cheap

- One SFV Dictionary parse answers both the §4 view and the §7 error in the frame decoders — never two parses (`lib/fast/priority/field.rb:133-144`; `test/fast/priority/allocations.rb:16-20`).
- The member filter allocates nothing when nothing is ignored (the parsed frozen Hash is the members Hash) (`lib/fast/priority/field.rb:164-186`).
- The unknown view is derived lazily and shared when empty (`lib/fast/priority/parameters.rb:20-21,157-167`); `to_s` serializes into the one output String fast-sfv builds.
- The §4 positioning scan runs only on the strict path (`parse!`), never on `parse` (`lib/fast/priority/field.rb:14-50`).

## The benchmark

Measured in both runtime modes — the plain interpreter (the no-JIT floor) and YJIT (the compiling runtime, the common production configuration):

```sh
BUNDLE_GEMFILE=gems/priority/gems.rb bundle exec ruby gems/priority/benchmark/priority.rb
BUNDLE_GEMFILE=gems/priority/gems.rb bundle exec ruby --yjit gems/priority/benchmark/priority.rb
```

Full mode: 5 s timed + 1 s warmup per operation, both modes from one measurement session. Pins benchmark-ips 2.15.1.

No other Ruby implementation of RFC 9218 exists — starry, the family's reference comparator for fast-sfv, implements the Structured Fields substrate, not this field — so there is no comparator row; the numbers hold fast-priority to its own budgets (the objects/call column is the discipline the tests freeze, computed on the same inputs as the budget tests); i/s is indicative.

Interpreter mode:

```
ruby 4.0.10 (2026-11-19 revision a704b7cd95) +PRISM [arm64-darwin25]; fast-priority 0.1.0
the numbers hold fast-priority to its own budgets (the objects/call column); i/s is indicative
```

| operation | i/s | ±% | objects/call |
|---|---|---|---|
| Fast::Priority.parse | 479,870 | 0.38 | 8.00 |
| Fast::Priority.parse (malformed) | 868,194 | 0.75 | 8.00 |
| Parameters#to_s | 748,968 | 0.54 | 1.00 |
| Parameters#merge | 2,600,594 | 0.36 | 2.00 |
| H2.encode_payload | 673,666 | 0.38 | 2.00 |
| H2.decode_payload | 434,585 | 0.36 | 10.00 |
| H3.encode_payload | 644,353 | 0.82 | 2.00 |
| H3.decode_payload | 423,143 | 0.24 | 10.00 |

YJIT mode:

```
ruby 4.0.10 (2026-11-19 revision a704b7cd95) +YJIT +PRISM [arm64-darwin25]; fast-priority 0.1.0
the numbers hold fast-priority to its own budgets (the objects/call column); i/s is indicative
```

| operation | i/s | ±% | objects/call |
|---|---|---|---|
| Fast::Priority.parse | 1,645,522 | 2.11 | 8.00 |
| Fast::Priority.parse (malformed) | 1,460,117 | 1.52 | 9.00 |
| Parameters#to_s | 3,279,028 | 1.96 | 1.00 |
| Parameters#merge | 5,646,321 | 3.04 | 2.00 |
| H2.encode_payload | 2,575,781 | 1.96 | 2.00 |
| H2.decode_payload | 1,392,183 | 2.06 | 10.00 |
| H3.encode_payload | 2,440,998 | 2.22 | 2.00 |
| H3.decode_payload | 1,442,809 | 1.95 | 10.00 |

Reading the two tables: objects/call is mode-independent on seven of the eight rows; the malformed-parse row measures one object more under YJIT than under the interpreter (9 vs 8) — the raised-and-rescued Dictionary failure measures differently under the compiled runtime; the budgets are frozen under the interpreter, the mode the test suite runs in, and hold there.

Benchmark samples: parse `"u=5, i"`, malformed `"!!"`, `to_s`/`merge` on parsed values (`"u=5, i"` and right side `"u=1"`), H2 encode/decode on stream 5 / `(["00000005"].pack("H*") << "u=5, i")`, H3 encode/decode on element 4 / `(["04"].pack("H*") << "u=5, i")` — the same inputs as the budget tests.

Caveats:

- benchmark-ips timings vary run to run (the ±% column) and across machines — the i/s column is indicative, not contractual.
- objects/call is deterministic: one settled call's object count with GC disabled over a 10,000-call batch — it is the column the gem holds itself to.
- The ruby/platform banner above each table names the measured environment; both modes ran on the same machine and ruby build in one session.

## The allocation budgets

Budgets are frozen in `test/fast/priority/allocations.rb` (measured on Ruby 4.0.10) — a regression the tests catch.

| operation | input | bound | measured |
|---|---|---|---|
| parse | `"u=5, i"` | < 9 | 8 — the engine, the SFV Parser, the dict Hash + 2 keys + 2 Items, the Parameters |
| parse (malformed) | `"!!"` | < 9 | 8 — the engine, the SFV failure path, the all-defaults Parameters + its Hash |
| to_s | the parsed `"u=5, i"` | < 2 | 1 — the output String only |
| merge | left `"u=5, i"`, right `"u=1"` | < 3 | 2 — the merged Hash and the new Parameters |
| H2.encode_payload | `(5, parsed "u=1, i")` | < 3 | 2 — the 4-byte word pack and the `to_s` |
| H2.decode_payload | `(["00000005"].pack("H*") << "u=5, i")` | < 11 | 10 — the byteslice, the engine, the one SFV parse (Parser, Hash, 2 keys, 2 Items), the Parameters, the Frame |
| H3.encode_payload | `(4, parsed "u=1, i")` | < 3 | 2 — the varint pack and the `to_s` |
| H3.decode_payload | `(["04"].pack("H*") << "u=5, i")` | < 11 | 10 — the same shape as H2 decode |

The benchmark table's objects/call column and these budgets are the same discipline on the same inputs (the interpreter column matches each budget's measured count).

## How to reproduce

Benchmark:

```sh
BUNDLE_GEMFILE=gems/priority/gems.rb bundle install
BUNDLE_GEMFILE=gems/priority/gems.rb bundle exec ruby gems/priority/benchmark/priority.rb
BUNDLE_GEMFILE=gems/priority/gems.rb bundle exec ruby --yjit gems/priority/benchmark/priority.rb
```

Quick mode for sanity-check (0.5 s time / 0.2 s warmup, not for publishing):

```sh
BENCH_QUICK=1 BUNDLE_GEMFILE=gems/priority/gems.rb bundle exec ruby gems/priority/benchmark/priority.rb
```

Allocation measurement: `GC.stat(:total_allocated_objects)` deltas averaged over runs, everything a measured block touches a local; GC disabled over a 10,000-call batch.

Caveats: benchmark-ips timings vary run to run and across machines; objects/call is deterministic per ruby; the measured environment is named by the ruby banner; both modes ran on the same machine and ruby build in one session.
