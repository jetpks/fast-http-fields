# Why every gem has allocation budgets

Every gem in this family carries a set of tests that count the Ruby objects its operations allocate — and fails if the count grows. Not a benchmark on a website: a test, run with the suite, on every commit. Why a field-parsing library would test that is this page.

## The budgets are tests

What one looks like — a verbatim quote from the repo (the sfv suite's own budget test):

```text
it "parses a bare item in two objects" do
  input = "42"
  Fast::SFV.parse_item(input)
  # The Parser instance and the Item.
  expect(allocations { Fast::SFV.parse_item(input) }).to be(:<, 3)
end
```

How the measurement works: `GC.stat(:total_allocated_objects)` before and after a batch, averaged — the helper beside the test. The budget is an upper bound the test asserts, frozen once measured. All five gems carry one such file (`test/fast/<gem>/allocations.rb` in each).

## Why allocations

A field parser runs on every request, sometimes several times — a proxy reads Priority, Digest and Proxy-Status on the same message, the composition the family exists for. Every object allocated is work the garbage collector does later. In a server, that work is latency spread across requests.

The family's design choices follow the same line: hand-rolled byte-index scanners (no regex-per-token object churn), frozen value objects built once per parse, append-only serialization into one buffer, no hidden buffers or lazy enumerators — fiber-friendly by construction.

The budgets keep the next change honest: the test fails when a small cleanup quietly doubles a hot path's allocations.

## The numbers live in each gem

Where the measured numbers are — linked, never forked: each gem's `docs/explanation/performance.md` carries its both-mode benchmark tables (interpreter and YJIT from one measurement session) with the methodology and caveats:

- [fast-sfv performance](../../gems/sfv/docs/explanation/performance.md)
- [fast-priority performance](../../gems/priority/docs/explanation/performance.md)
- [fast-digest performance](../../gems/digest/docs/explanation/performance.md)
- [fast-proxy-status performance](../../gems/proxy_status/docs/explanation/performance.md)
- [fast-client-cert performance](../../gems/client_cert/docs/explanation/performance.md)

The top level states no numbers of its own: no iteration counts, no objects per call, no machine banner — those are per-gem facts, each measured on the gem's own benchmark, and this page links them.

## What the budgets are not

Not a speed race — the benchmarks hold the family to its own budgets, they do not rank it against other libraries (fast-sfv's page credits starry as its comparator and states the philosophy — linked, not restated). Allocation counts are deterministic where timings are not, which is why the budgets are tests and the timings are pages.

For how the whole family is verified: [family map](../reference/family-map.md) — section "How the family is verified."
