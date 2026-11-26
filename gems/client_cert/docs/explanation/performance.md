# Performance and allocation budgets

How the paths stay allocation-lean; the both-mode benchmark tables and the allocation budgets, with methodology and caveats.

## Design goals

The hot paths ride the family substrate: every field operation is one RFC 9651 Item or List parse through fast-sfv, so this gem's discipline is to add as little as possible on top — the shared Checks seam, the frozen value objects, the shared empty value, one output String per emission, and the RFC 9440 §2.1 string surgery as plain text manipulation.

## How the paths stay cheap

- The lenient parse is the substrate parse rescued raw — one walk answers both, never two parses; the wrap is spent only on failure.
- The Cert's fall answers nil — nothing is built on the fall; the Chain's fall answers the shared frozen EMPTY singleton, built once at load.
- The value objects are `allocate` + `hold` on the parse path — no re-validation, no member copy (the parsed Items ARE the held members; the ders view is derived once).
- `to_s` serializes into the one output String fast-sfv builds.
- The PEM helpers are the RFC 9440 §2.1 surgery: split, strip, join — no parsing, no encoding, the strip only where the textual form needs it.

## The benchmark

No other Ruby implementation of RFC 9440 exists — starry, the family's reference comparator for fast-sfv, implements the Structured Fields substrate, not these fields — so there is no comparator row; the numbers hold fast-client-cert to its own budgets (the objects/call column is the discipline the tests freeze, computed on the SAME inputs as the budget tests); i/s is indicative.

Both modes ran on the same machine and ruby build in one session:

```
ruby 4.0.10 (2026-11-19 revision a704b7cd95) +PRISM [arm64-darwin25]; fast-client-cert 0.1.0
the numbers hold fast-client-cert to its own budgets (the objects/call column); i/s is indicative
| operation | i/s | ±% | objects/call |
|---|---|---|---|
| Cert.parse | 12,240 | 1.01 | 4.00 |
| Cert.parse (malformed) | 1,114,704 | 1.03 | 4.00 |
| Cert.parse! | 12,389 | 0.75 | 4.00 |
| Cert.valid? | 12,296 | 0.85 | 4.00 |
| Cert.new | 4,668,628 | 0.90 | 2.00 |
| Cert#to_s | 38,416 | 1.11 | 1.00 |
| Chain.parse | 5,116 | 0.70 | 8.00 |
| Chain.parse (split lines) | 4,974 | 0.74 | 9.00 |
| Chain.parse (malformed) | 983,884 | 1.07 | 5.00 |
| Chain.parse (member fall) | 342,801 | 1.00 | 5.00 |
| Chain.parse! | 5,131 | 0.74 | 8.00 |
| Chain.valid? | 5,129 | 0.86 | 8.00 |
| Chain.new | 1,948,381 | 0.95 | 5.00 |
| Chain#to_s | 16,503 | 0.96 | 1.00 |
| Chain#split | 16,218 | 1.01 | 5.00 |
| pem_to_field | 529,535 | 0.89 | 28.00 |
| field_to_pem | 243,377 | 1.00 | 12.00 |
| pems_to_field | 208,128 | 0.91 | 66.00 |
| field_to_pems | 46,405 | 7.42 | 35.00 |
```

```
ruby 4.0.10 (2026-11-19 revision a704b7cd95) +YJIT +PRISM [arm64-darwin25]; fast-client-cert 0.1.0
the numbers hold fast-client-cert to its own budgets (the objects/call column); i/s is indicative
| operation | i/s | ±% | objects/call |
|---|---|---|---|
| Cert.parse | 97,376 | 1.13 | 4.00 |
| Cert.parse (malformed) | 1,709,942 | 1.68 | 5.00 |
| Cert.parse! | 97,747 | 0.92 | 4.00 |
| Cert.valid? | 97,625 | 1.19 | 4.00 |
| Cert.new | 14,349,314 | 2.58 | 2.00 |
| Cert#to_s | 277,120 | 1.82 | 1.00 |
| Chain.parse | 41,099 | 1.32 | 8.00 |
| Chain.parse (split lines) | 40,211 | 1.08 | 9.00 |
| Chain.parse (malformed) | 1,558,211 | 1.52 | 6.00 |
| Chain.parse (member fall) | 1,565,710 | 1.69 | 5.00 |
| Chain.parse! | 41,101 | 1.03 | 8.00 |
| Chain.valid? | 41,146 | 1.09 | 8.00 |
| Chain.new | 4,105,648 | 2.23 | 5.00 |
| Chain#to_s | 122,261 | 1.29 | 1.00 |
| Chain#split | 116,637 | 0.89 | 5.00 |
| pem_to_field | 684,102 | 1.50 | 28.00 |
| field_to_pem | 248,324 | 1.06 | 12.00 |
| pems_to_field | 264,108 | 1.26 | 66.00 |
| field_to_pems | 42,790 | 2.19 | 35.00 |
```

Objects/call is mode-independent on sixteen of the nineteen rows; the two malformed-parse rows — `Cert.parse (malformed)` and `Chain.parse (malformed)` — measure one object more under YJIT than under the interpreter (5 vs 4, 6 vs 5) because the raised-and-rescued substrate failure measures differently under the compiled runtime (the same exception-path phenomenon the fast-priority, fast-digest and fast-proxy-status perf pages document); the member-violation fall, which builds no error on the lenient path, is mode-independent at 5. The budgets are frozen under the interpreter, the mode the test suite runs in, and hold there.

The allocation tests' header comments narrate per-path counts measured under the suite's coverage instrumentation, which read one object above the benchmark's deterministic bare-runtime counts on the three fall rows; the asserted bounds hold everywhere, and this page publishes the benchmark's own numbers.

benchmark-ips timings vary run to run and across machines; objects/call is deterministic per ruby; the measured environment is named by the ruby banner; both modes ran on the same machine and ruby build in one session.

## The allocation budgets

Frozen in `test/fast/client_cert/allocations.rb` (measured on Ruby 4.0.10) — a regression the tests catch. One row per budget test, same inputs as the benchmark:

| operation | input | bound | measured |
|---|---|---|---|
| Cert parse | the Figure 2 value | < 5 | 4 — the Fast::SFV Parser, the Item with its decoded base64 String, and the Cert value object |
| parse (malformed fall) | `"!!"` | < 7 | 4 — the SFV parse's failure path (the raised error with its message), rescued raw: nothing is built on the fall |
| strict parse | the Figure 2 value | < 5 | 4 — the lenient path's own count: the wrap is spent only on failure |
| `valid?` | the Figure 2 value | < 5 | 4 — the parse path's own count: the mirror adds nothing |
| Cert construction | `"hello".b` | < 4 | 2 — the Item and the value object (the params Hash is the shared frozen constant) |
| Cert emit | the parsed Figure 2 value | < 2 | 1 — the output String only |
| Chain parse | the Figure 3 value | < 9 | 8 — the Parser, the list Array with two Items and two decoded Strings, the value object and its ders view |
| parse (split lines) | the two member values, the second with a leading space | < 13 | 9 — the substrate's own line joining, then the parse path's count |
| parse (malformed fall) | `"!!"` | < 8 | 5 — the SFV failure path, rescued raw (the EMPTY singleton is built once at load) |
| parse (member fall) | `":aGVsbG8=:, 5"` | < 10 | 5 — the List parse itself; no error is constructed on the lenient path |
| strict parse | the Figure 3 value | < 9 | 8 — the lenient path's own count (the Scan and the wrap are spent only on failure) |
| `valid?` | the Figure 3 value | < 9 | 8 — the parse path's own count |
| Chain construction | `["hello".b, "world".b]` | < 9 | 5 — the items Array, the two Items, the value object and its ders view |
| emit | the parsed Figure 3 value | < 2 | 1 — the output String only: the members append into the one buffer |
| split | `whole.split(1)` on the parsed Figure 3 chain | < 6 | 5 — the lines Array, one slice Array and one serialization String per line |
| pem_to_field | the Figure 1 first block | < 29 | 28 — the split Array with one String per line, the payload slice, the stripped payload lines, the joined base64 and the field value |
| field_to_pem | the Figure 2 value | < 14 | 12 — the validated interior slice, the block String and one 64-character slice per payload line (the armor appends into the buffer in place) |
| pems_to_field | the Figure 1 second and third blocks | < 68 | 66 — the per-block surgery twice, then the joined members |
| field_to_pems | the Figure 3 value | < 38 | 35 — the member split with one String per member, the stripped members, and the per-member blocks |

The benchmark table's objects/call column and these budgets are the same discipline on the same inputs (the interpreter column matches each row's measured count).

## How to reproduce

```sh
BUNDLE_GEMFILE=gems/client_cert/gems.rb bundle exec ruby gems/client_cert/benchmark/client_cert.rb
BUNDLE_GEMFILE=gems/client_cert/gems.rb bundle exec ruby --yjit gems/client_cert/benchmark/client_cert.rb
```

Allocation-measurement method: `GC.stat` deltas averaged, GC disabled over the batch, everything a measured block touches a local.

Caveats: benchmark-ips timings vary run to run and across machines; objects/call is deterministic per ruby (one settled call's object count, GC disabled over a 10,000-call batch) — the column the gem holds itself to; the measured environment is named by the ruby banner; both modes ran on the same machine and ruby build in one session. Pins benchmark-ips 2.15.1; full mode = 5 s timed + 1 s warmup per operation, both modes from one measurement session.
