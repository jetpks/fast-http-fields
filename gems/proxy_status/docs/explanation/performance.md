# Performance and allocation budgets

## Design goals

The hot paths ride the family substrate: every field operation is one RFC 9651 parse through fast-sfv, so this gem's discipline is to add as little as possible on top — the one-walk/two-policy parse (the lenient walk IS the strict walk with the checks off), the frozen value objects over the parsed members, the shared frozen empty values, one output String per emission.

## How the paths stay cheap

- The two List fields share one engine — Proxy-Status and Cache-Status answer alike by construction.
- The fail-closed fall answers the shared frozen empty value (one object, stable identity).
- The positioning `Scan` runs only where an error needs an offset — the clean paths pay nothing for positioning.
- The value object is `allocate` + `hold` on the parse path — no re-validation, no member copy.
- `to_s` serializes into the one output String fast-sfv builds, `""` when nothing is held.
- `append` reuses the held members — a copy, the new member, the new value: no re-parse, no re-emit.

## The benchmark

No other Ruby implementation of RFC 9209, 9211 or 9213 exists — starry, the family's reference comparator for fast-sfv, implements the Structured Fields substrate, not these fields — so there is no comparator row; the numbers hold fast-proxy-status to its own budgets (the objects/call column is the discipline the tests freeze, computed on the SAME inputs as the budget tests); i/s is indicative.

Measured on this machine, both modes from one session:

```
ruby 4.0.10 (2026-11-19 revision a704b7cd95) +PRISM [arm64-darwin25]; fast-proxy-status 0.1.0
the numbers hold fast-proxy-status to its own budgets (the objects/call column); i/s is indicative
| operation | i/s | ±% | objects/call |
|---|---|---|---|
| ProxyStatus.parse | 243,048 | 0.95 | 13.00 |
| ProxyStatus.parse (malformed) | 663,125 | 0.90 | 7.00 |
| ProxyStatus.parse (member fall) | 227,203 | 0.78 | 10.00 |
| ProxyStatus.parse! | 237,806 | 0.19 | 13.00 |
| ProxyStatus.valid? | 237,863 | 0.16 | 13.00 |
| ProxyStatus::Hop.new | 4,470,285 | 0.23 | 2.00 |
| ProxyStatus#append (held) | 2,097,718 | 0.15 | 4.00 |
| ProxyStatus.append | 359,709 | 0.40 | 16.00 |
| ProxyStatus.promote | 131,448 | 1.07 | 28.00 |
| ProxyStatus#to_s | 643,186 | 0.94 | 1.00 |
| CacheStatus.parse | 147,614 | 0.65 | 17.00 |
| CacheStatus.parse (three-line) | 96,009 | 0.72 | 32.00 |
| CacheStatus.parse (malformed) | 656,618 | 0.56 | 7.00 |
| CacheStatus.parse (member fall) | 211,327 | 0.22 | 10.00 |
| CacheStatus.parse! | 271,419 | 0.26 | 11.00 |
| CacheStatus.valid? | 134,719 | 0.59 | 17.00 |
| CacheStatus::Cache.new | 3,637,076 | 0.12 | 2.00 |
| CacheStatus#append (held) | 1,897,318 | 0.14 | 4.00 |
| CacheStatus.append | 250,683 | 0.36 | 15.00 |
| CacheStatus#to_s | 225,948 | 0.31 | 1.00 |
| TargetedCacheControl.parse | 382,578 | 0.12 | 9.00 |
| TargetedCacheControl.parse (malformed) | 749,095 | 0.87 | 7.00 |
| TargetedCacheControl.parse (flagged) | 561,975 | 0.18 | 8.00 |
| TargetedCacheControl.parse! | 382,847 | 0.16 | 9.00 |
| TargetedCacheControl.valid? | 382,943 | 0.19 | 9.00 |
| TargetedCacheControl.new | 1,407,696 | 0.52 | 5.00 |
| TargetedCacheControl#to_s | 530,755 | 0.31 | 1.00 |
```

```
ruby 4.0.10 (2026-11-19 revision a704b7cd95) +YJIT +PRISM [arm64-darwin25]; fast-proxy-status 0.1.0
the numbers hold fast-proxy-status to its own budgets (the objects/call column); i/s is indicative
| operation | i/s | ±% | objects/call |
|---|---|---|---|
| ProxyStatus.parse | 1,031,378 | 0.82 | 13.00 |
| ProxyStatus.parse (malformed) | 925,512 | 0.88 | 8.00 |
| ProxyStatus.parse (member fall) | 463,823 | 0.55 | 10.00 |
| ProxyStatus.parse! | 1,003,987 | 1.21 | 13.00 |
| ProxyStatus.valid? | 1,000,461 | 1.17 | 13.00 |
| ProxyStatus::Hop.new | 12,465,979 | 2.38 | 2.00 |
| ProxyStatus#append (held) | 5,839,032 | 3.58 | 4.00 |
| ProxyStatus.append | 1,192,649 | 1.83 | 16.00 |
| ProxyStatus.promote | 517,305 | 0.86 | 28.00 |
| ProxyStatus#to_s | 3,400,173 | 1.85 | 1.00 |
| CacheStatus.parse | 705,480 | 1.54 | 17.00 |
| CacheStatus.parse (three-line) | 358,542 | 0.82 | 32.00 |
| CacheStatus.parse (malformed) | 924,221 | 1.07 | 8.00 |
| CacheStatus.parse (member fall) | 420,010 | 0.38 | 10.00 |
| CacheStatus.parse! | 1,065,120 | 1.50 | 11.00 |
| CacheStatus.valid? | 568,478 | 1.27 | 17.00 |
| CacheStatus::Cache.new | 11,065,987 | 4.00 | 2.00 |
| CacheStatus#append (held) | 5,406,205 | 3.03 | 4.00 |
| CacheStatus.append | 937,863 | 0.94 | 15.00 |
| CacheStatus#to_s | 486,536 | 0.48 | 1.00 |
| TargetedCacheControl.parse | 1,495,266 | 1.49 | 9.00 |
| TargetedCacheControl.parse (malformed) | 1,034,151 | 1.52 | 8.00 |
| TargetedCacheControl.parse (flagged) | 2,029,935 | 1.68 | 8.00 |
| TargetedCacheControl.parse! | 1,501,808 | 1.66 | 9.00 |
| TargetedCacheControl.valid? | 1,501,764 | 1.81 | 9.00 |
| TargetedCacheControl.new | 4,757,665 | 2.69 | 5.00 |
| TargetedCacheControl#to_s | 1,699,855 | 1.51 | 1.00 |
```

Objects/call is mode-independent on twenty-four of the twenty-seven rows; the three malformed-fall rows (the raised-and-rescued substrate failure) measure one object more under YJIT than under the interpreter (8 vs 7) — the same class of exception-path anomaly the fast-priority and fast-digest perf pages document; the budgets are frozen under the interpreter, the mode the test suite runs in, and hold there.

Objects/call depends on the input's content, not only its shape — an identifier long enough to cross Ruby's embedded-string threshold costs one object more than a short one (the §2 two-member example's 21-byte first member parses in 13 objects where two short members parse in 12) — which is why the benchmark fixes its inputs and this page names them.

The benchmark's inputs, which this page's objects/call names: the Proxy-Status parses on §2's two-intermediary example `"revproxy1.example.net, ExampleCDN"`, the malformed falls on `"!!"`, the member-violation falls on `"ExampleCDN, 5"` / `"ExampleCache, 5"`, the Cache-Status parses on §3's two-layer example and the three-line example (the Array of lines), the Cache-Status strict parse on §3's polite-cache example `"ExampleCache; hit; ttl=376"`, the targeted parses on §3.1's directive values `"max-age=600, no-store"` and the flagged `"max-age=60.5"`, the constructions on the member/member-Hash forms, the appends on `"a, b"` / `"a; hit"` / `"ExampleCache; hit; ttl=376"` with the member and params held outside the measured call, promote on §2's trailer pair `"SomeOtherProxy, ThisProxy"` + `"ThisProxy; error=read_timeout"`, `to_s` on the parsed §2 / two-layer / directive values — the SAME inputs as the budget tests.

## The allocation budgets

Frozen in `test/fast/proxy_status/allocations.rb` (measured on Ruby 4.0.10) — a regression the tests catch. The benchmark table's objects/call column and these budgets are the same discipline on the same inputs; the allocations.rb header comments narrate counts measured under the suite's coverage instrumentation, which read one or two objects above the bare-runtime counts on seven rows — the bounds (what the tests assert) hold in both contexts, and the benchmark's own deterministic numbers are what the tables publish.

| operation | input | bound | measured |
|---|---|---|---|
| Proxy-Status parse | `"revproxy1.example.net, ExampleCDN"` | < 14 | 13 |
| parse (malformed fall) | `"!!"` | < 9 | 7 |
| parse (member fall) | `"ExampleCDN, 5"` | < 12 | 10 |
| strict parse | `"revproxy1.example.net, ExampleCDN"` | < 14 | 13 |
| `valid?` | `"revproxy1.example.net, ExampleCDN"` | < 14 | 13 |
| Hop construction | `Token.new("x")` | < 3 | 2 |
| append (held) | `parse("a, b")` + `Token.new("c")` | < 5 | 4 |
| append (String) | `append("a, b", Token)` | < 18 | 16 |
| promote | `"SomeOtherProxy, ThisProxy"` + `"ThisProxy; error=read_timeout"` | < 31 | 28 |
| emit | the parsed §2 value | < 2 | 1 |
| Cache-Status parse (two-layer) | `'OriginCache; hit; ttl=1100, "CDN Company Here"; hit; ttl=545'` | < 18 | 17 |
| parse (three-line) | `["ReverseProxyCache; hit", "ForwardProxyCache; fwd=uri-miss; collapsed; stored", "BrowserCache; fwd=uri-miss"]` | < 33 | 32 |
| parse (malformed fall) | `"!!"` | < 9 | 7 |
| parse (member fall) | `"ExampleCache, 5"` | < 12 | 10 |
| strict parse | `"ExampleCache; hit; ttl=376"` | < 12 | 11 |
| `valid?` | `'OriginCache; hit; ttl=1100, "CDN Company Here"; hit; ttl=545'` | < 18 | 17 |
| Cache construction | `Token.new("x")` | < 3 | 2 |
| append (held) | `parse("a; hit")` + `Token.new("c")` | < 5 | 4 |
| append (String) | `append("ExampleCache; hit; ttl=376", Token)` | < 16 | 15 |
| emit | the parsed two-layer value | < 2 | 1 |
| targeted parse | `"max-age=600, no-store"` | < 10 | 9 |
| parse (malformed fall) | `"!!"` | < 9 | 7 |
| parse (flagged) | `"max-age=60.5"` | < 9 | 8 |
| strict parse | `"max-age=600, no-store"` | < 10 | 9 |
| `valid?` | `"max-age=600, no-store"` | < 10 | 9 |
| construction | `{ "max-age" => 600 }` | < 6 | 5 |
| emit | the parsed directive value | < 2 | 1 |

## How to reproduce

```sh
bundle install
BUNDLE_GEMFILE=gems/proxy_status/gems.rb bundle exec ruby gems/proxy_status/benchmark/proxy_status.rb
BUNDLE_GEMFILE=gems/proxy_status/gems.rb bundle exec ruby --yjit gems/proxy_status/benchmark/proxy_status.rb
```

Allocation measurement method: `GC.stat` deltas averaged, GC disabled over the batch, everything a measured block touches a local. Full mode = 5 s timed + 1 s warmup per operation, both modes from one measurement session. Pins benchmark-ips 2.15.1.

Caveats: benchmark-ips timings vary run to run and across machines; objects/call is deterministic per ruby and per input; the measured environment is named by the ruby banner; both modes ran on the same machine and ruby build in one session.
