# Performance and allocation budgets

## Design goals

The hot path is the family substrate — every fast-http-fields field operation passes through Structured Field Values, so parse and emit are built zero-waste: hand-rolled byte-index scanners (no regex-per-token), append-only emission, frozen value objects.

## How the parser stays cheap

- One `Parser` instance per parse, byte-index walking, first-byte dispatch, frozen 256-entry character-class tables.
- Strings are sliced, not re-assembled: the common case is one contiguous `byteslice` per string.
- Integers accumulate in place — no intermediate String, a 15-digit value stays inside immediate Integers.
- Items with no parameters share one frozen empty Hash — a bare item costs no parameter allocation.

## How the serializer stays cheap

- One output String per emission — the only object an emission allocates; tokens, keys and strings append whole; integers spell by division against a `POWERS` table.
- The one unavoidable temporary: the decimal's `Float#to_s` text its digits are read from.

## The benchmark

Measured in both runtime modes — the plain interpreter (the no-JIT floor) and YJIT (the compiling runtime, the common production configuration):

```sh
BUNDLE_GEMFILE=gems/sfv/gems.rb bundle exec ruby gems/sfv/benchmark/sfv.rb
BUNDLE_GEMFILE=gems/sfv/gems.rb bundle exec ruby --yjit gems/sfv/benchmark/sfv.rb
```

Full mode: 5 s timed + 1 s warmup per operation, both modes. Pins: benchmark-ips 2.15.1, starry 0.2.0.

starry is the RFC 8941 reference implementation — a reference comparison, not a ranking; the numbers hold fast-sfv to its own budgets (the objects/call column); the compared surface is the RFC 8941 subset both libraries implement. starry is a dev-only comparator in the benchmark bundle, never a runtime dependency.

Interpreter mode:

```
ruby 4.0.10 (2026-11-19 revision a704b7cd95) +PRISM [arm64-darwin25]; fast-sfv 0.1.0; starry 0.2.0
starry is the RFC 8941 reference implementation: a reference comparison, not a ranking.
```

| operation | i/s | ±% | objects/call |
|---|---|---|---|
| Fast::SFV.parse_item | 256,591 | 0.86 | 5.00 |
| Starry.parse_item | 379,186 | 1.10 | 26.00 |
| Fast::SFV.parse_list | 197,013 | 0.70 | 14.00 |
| Starry.parse_list | 130,454 | 0.69 | 81.00 |
| Fast::SFV.parse_dict | 207,450 | 0.42 | 15.00 |
| Starry.parse_dictionary | 133,467 | 0.51 | 74.00 |
| Fast::SFV.serialize_item | 381,765 | 0.86 | 1.00 |
| Starry.serialize (item) | 861,390 | 0.57 | 13.00 |
| Fast::SFV.serialize_list | 305,404 | 0.79 | 1.00 |
| Starry.serialize (list) | 310,671 | 0.88 | 50.00 |
| Fast::SFV.serialize_dict | 287,994 | 0.65 | 1.00 |
| Starry.serialize (dictionary) | 263,997 | 0.46 | 49.00 |

YJIT mode:

```
ruby 4.0.10 (2026-11-19 revision a704b7cd95) +YJIT +PRISM [arm64-darwin25]; fast-sfv 0.1.0; starry 0.2.0
starry is the RFC 8941 reference implementation: a reference comparison, not a ranking.
```

| operation | i/s | ±% | objects/call |
|---|---|---|---|
| Fast::SFV.parse_item | 1,669,457 | 1.44 | 5.00 |
| Starry.parse_item | 520,315 | 0.45 | 26.00 |
| Fast::SFV.parse_list | 962,235 | 1.56 | 14.00 |
| Starry.parse_list | 181,733 | 0.47 | 81.00 |
| Fast::SFV.parse_dict | 917,566 | 1.34 | 15.00 |
| Starry.parse_dictionary | 183,649 | 0.44 | 74.00 |
| Fast::SFV.serialize_item | 2,273,364 | 2.01 | 1.00 |
| Starry.serialize (item) | 1,199,315 | 2.02 | 13.00 |
| Fast::SFV.serialize_list | 1,338,120 | 1.67 | 1.00 |
| Starry.serialize (list) | 412,648 | 0.72 | 50.00 |
| Fast::SFV.serialize_dict | 1,137,621 | 1.59 | 1.00 |
| Starry.serialize (dictionary) | 359,093 | 0.62 | 49.00 |

Reading the two tables: in the interpreter, per-byte scanning pays Ruby
VM dispatch on every byte, so starry — whose StringScanner regexes
consume whole tokens in C — takes the two item-shaped cells, where most
of the sample is one long string. With YJIT the scanner loops compile to
machine code and every cell is ahead, by 1.9× to 5.3× on these samples.
The objects/call column is identical in both modes — allocation counts
are mode-independent — and it is the column fast-sfv holds itself to;
i/s is indicative.

Benchmark samples: item `"2;foourl=\"https://foo.example.com/\""`, list `"(\"foo\" \"bar\");a=1, sugar, 42"`, dictionary `"a=1, b;foo=bar, c=(1 2)"`.

Caveats:

- benchmark-ips timings vary run to run (the ±% column) and across machines — the i/s column is indicative, not contractual.
- objects/call is deterministic: one settled call's object count with GC disabled over a 10,000-call batch — it is the column fast-sfv holds itself to.
- The ruby/platform banner above each table names the measured environment; both modes ran on the same machine and ruby build in one session, and YJIT compiles during the warmup phase, so its table reports compiled throughput.
- starry is the RFC 8941 reference implementation; the compared surface is the RFC 8941 subset both libraries implement.

## The allocation budgets

Budgets are frozen in `test/fast/sfv/allocations.rb` (measured on Ruby 4.0.10) — a regression the tests catch.

Parse budgets:

| operation | input | objects |
|---|---|---|
| parse_item | `"42"` (bare item) | 2 — the Parser and the Item |
| parse_item | `"sugar"` (token) | 4 — Parser, Item, the content slice, the Token |
| parse_item | `"5; foo=bar; a=1; b=?0"` (parameters) | 8 — Parser, Item, params Hash, 3 key Strings, token slice + Token |
| parse_item | `"\"foo bar\""` (string) | 3 — Parser, Item, one content slice |
| parse_item | `":aGVsbG8=:"` (byte sequence) | 3 — Parser, Item, decoded byte String |
| parse_item | `"%\"f%c3%bc\""` (display string) | 4 — Parser, Item, DisplayString, decoded buffer |
| parse_list | `"sugar, tea, rum"` (three tokens) | 11 — Parser, members Array, 3 Items, each token's slice + Token |
| parse_list | `["\"foo", "bar\""]` (multi-line) | 5 — Parser, joined value, members Array, Item, content slice |
| parse_dict | `"a=1;b=2, c=(1 2)"` (mixed with inner list) | 11 — Parser, Hash + 3 keys, 2 Items, params Hash + key, InnerList + items Array + 2 Items |

Serialize budgets:

| operation | value | objects |
|---|---|---|
| serialize_item | `Item.new(42, {})` | 1 — the output String only |
| serialize_item | `Item.new(5, { "foo" => Token.new("bar"), "a" => 1, "b" => false, "c" => true })` | 1 — keys, Token and digits append into the one buffer |
| serialize_item | `Item.new(1.23, {})` (decimal) | 2 — output String + the Float#to_s text |
| serialize_list | `[Item.new(Token.new("a"), {}), InnerList.new([Item.new(2, {})], { "a" => 1 })]` | 1 — no per-member temporaries |
| serialize_dict | `{ "a" => Item.new(false, {}), "b" => Item.new(true, { "foo" => Token.new("bar") }), "c" => InnerList.new([Item.new(1, {}), Item.new(2, {})], {}) }` | 1 — a decimal member would add its 1 text object |

Notes:

- The benchmark table's objects/call column and these budgets are the same discipline measured on different inputs: the three serialize rows read 1.00, matching the "one object" budgets; parse rows are quoted with the benchmark's own samples, never against the budget inputs.
- The 100-member list is still 1 — the emission appends into one buffer, so the serialize budgets hold "whatever the member count".
- A token value costs its content slice plus the Token, measured one object more than the slice alone, no intern cache.

See [Why the Ruby type is the wire-type tag](wire-type-tag.md) for the Token design.

## How to reproduce

Benchmark:

```sh
BUNDLE_GEMFILE=gems/sfv/gems.rb bundle install --local
BUNDLE_GEMFILE=gems/sfv/gems.rb bundle exec ruby gems/sfv/benchmark/sfv.rb
BUNDLE_GEMFILE=gems/sfv/gems.rb bundle exec ruby --yjit gems/sfv/benchmark/sfv.rb
```

Quick mode for sanity-check (0.5 s time / 0.2 s warmup, not for publishing):

```sh
BENCH_QUICK=1 BUNDLE_GEMFILE=gems/sfv/gems.rb bundle exec ruby gems/sfv/benchmark/sfv.rb
```

Allocation measurement: `GC.stat(:total_allocated_objects)` deltas averaged over runs, everything a measured block touches a local.

Caveats: benchmark-ips timings vary run to run (the ±% column) and across machines; objects/call and the budgets are deterministic; the measured environment is named by the ruby banner line in the table.
