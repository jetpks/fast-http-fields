# The family map

Five gems, seven RFCs, one shared grammar. This page is the map: what each gem owns, what they all share, and where every piece of documentation lives.

## The five gems

| Gem | Fields | RFC(s) | Require | Module(s) | Current release | Docs |
|-----|--------|--------|---------|-----------|-----------------|------|
| [fast-sfv](../../gems/sfv/README.md) | Structured Field Values (the grammar itself) | RFC 9651 | `require "fast/sfv"` | `Fast::SFV` | 0.1.1 | [docs](../../gems/sfv/docs/) (10 leaves) |
| [fast-priority](../../gems/priority/README.md) | Priority, plus HTTP/2 and HTTP/3 PRIORITY_UPDATE frame payloads | RFC 9218 | `require "fast/priority"` | `Fast::Priority` | 0.1.0 | [docs](../../gems/priority/docs/) (10 leaves) |
| [fast-digest](../../gems/digest/README.md) | Content-Digest, Repr-Digest, Want-Content-Digest, Want-Repr-Digest | RFC 9530 | `require "fast/digest"` | `Fast::Digest` | 0.1.0 | [docs](../../gems/digest/docs/) (11 leaves) |
| [fast-proxy-status](../../gems/proxy_status/README.md) | Proxy-Status, Cache-Status, Targeted Cache Control (CDN-Cache-Control) | RFC 9209, 9211, 9213 | `require "fast/proxy_status"` | `Fast::ProxyStatus`, `Fast::CacheStatus`, `Fast::TargetedCacheControl` | 0.1.0 | [docs](../../gems/proxy_status/docs/) (14 leaves) |
| [fast-client-cert](../../gems/client_cert/README.md) | Client-Cert, Client-Cert-Chain | RFC 9440 | `require "fast/client_cert"` | `Fast::ClientCert` | 0.1.0 | [docs](../../gems/client_cert/docs/) (9 leaves) |

The four field gems each declare exactly one runtime dependency — `fast-sfv` — and nothing else anywhere in the family (fast-digest's stdlib digest use is a default gem, no dependency line). Ruby >= 3.4 and RubyGems >= 3.5.3 across all five.

## The shared substrate

Every field the family owns is a Structured Field Value — a value from RFC 9651's small type system (integers, strings, tokens, byte sequences, booleans, dates, lists, dictionaries). The field specs define semantics instead of string formats, and one grammar handles them all.

fast-sfv implements that grammar once. The four dependents parse and emit through it and add only their RFC's constraints. RFC 9651 obsoleted RFC 8941 — the grammar's whole history in one line.

What the dependents get from the substrate:

- The strict grammar — the whole family's error taxonomy inherits it.
- The canonical serialization — every gem's `to_s` is the same emit engine, so outputs round-trip and every reader sees the same bytes.
- The field-line combining every gem's entry points share — parsers combine all field lines in the same section (header or trailer) that match the field name into one comma-separated field value.
- The wire-type tags — a `Token` is a token, an ASCII-8BIT `String` is a byte sequence (see [wire-type tag](../../gems/sfv/docs/explanation/wire-type-tag.md)).

For the why: [the SFV substrate](../explanation/the-sfv-substrate.md). For the grammar's technical depth: the [sfv README](../../gems/sfv/README.md) and its [conformance page](../../gems/sfv/docs/reference/conformance.md) — the vendored httpwg corpus that referees the grammar.

## The shared mechanics

The family API contract, stated once:

- `parse` answers the RFC's recipient view and never raises on field content (`TypeError` only for a wrong input type — a caller bug).
- `parse!` is the strict truth, raising `Fast::<Name>::ParseError` positioned at the offending byte.
- `valid?` mirrors it with a boolean.
- `to_s` and construction are always strict — a sender never writes garbage.
- Results are frozen value objects.
- `Fast::<Name>::Error` branches into `ParseError` and `SerializeError` in every gem, both carrying the byte offset — one rescue guards any gem.

The input shapes: a String (one field value) or an Array of field lines, combined per RFC 9651 into one comma-separated value:

```ruby
require "fast/digest"
require "fast/client_cert"
require "fast/priority"

Fast::Digest::ContentDigest.parse(["sha-256=:AAAA:", "md5=:BBBB:"]).keys  # => ["sha-256", "md5"]
Fast::ClientCert::Chain.parse([":aGVsbG8=:", " :d29ybGQ=:"]).ders        # => ["hello", "world"]
Fast::Priority.parse(["u=5", "i"]).incremental                           # => true
```

What unreadable answers, field by field:

- Priority — the defaults (urgency 3, incremental false)
- Digest — the empty value (treated as absent, fail-closed)
- Client-Cert — nil (no certificate, unauthenticated)
- Proxy-Status — the shared empty value with unknown parameters preserved in the data (diagnostic leniency)
- fast-sfv itself — the one strict parse in the family, because it IS the grammar layer

See [why lenient-parse, strict-emit](../explanation/why-lenient-parse-strict-emit.md) for the reasoning.

And fast-priority additionally carries the h2/h3 PRIORITY_UPDATE payload codecs — byte-exact both directions, no connection state (see [frames](../../gems/priority/docs/reference/frames.md)).

## The registries

The pinned-as-data tables, one row each with its count:

| Registry | Constant | Count | RFC |
|----------|----------|-------|-----|
| Proxy error types with recommended statuses | `Fast::ProxyStatus::ERRORS` | 32 | RFC 9209 |
| Hash algorithms with their statuses | `Fast::Digest::ALGORITHMS` | 8 | RFC 9530 |
| Cache-Status parameters | `Fast::CacheStatus::PARAMETERS` | 8 | RFC 9211 |
| Cache-Status fwd reasons | `Fast::CacheStatus::FWD` | 8 | RFC 9211 |
| Targeted Cache Control directives | `Fast::TargetedCacheControl::DIRECTIVES` | 5 | RFC 9213 |

Unknown values pass through untouched everywhere — a future registration never breaks an old gem version (see [why registries are data](../explanation/why-registries-are-data.md); each registry's own per-gem reference page is linked above through the family map's gem rows).

## Where the documentation lives

The root tree — the family's own top level (8 leaves):

- Tutorial: [start-here](../tutorials/start-here.md) — one request, one response, five fields.
- How-to guides: [handle a request with Priority, Digest and Proxy-Status](../how-to-guides/handle-a-request-with-priority-digest-and-proxy-status.md) and [validate a client certificate and report the path](../how-to-guides/validate-a-client-cert-and-report-the-path.md).
- Reference: this page, the family map.
- Explanation: [why lenient-parse, strict-emit](../explanation/why-lenient-parse-strict-emit.md), [why registries are data](../explanation/why-registries-are-data.md), [why allocation budgets](../explanation/why-allocation-budgets.md), [the SFV substrate](../explanation/the-sfv-substrate.md).

The five per-gem trees — the technical layer (54 leaves in all):

| Gem | Tree | Leaves |
|-----|------|--------|
| fast-sfv | [docs](../../gems/sfv/docs/) | 10 (1 tutorial, 4 how-to guides, 2 reference, 3 explanation) |
| fast-priority | [docs](../../gems/priority/docs/) | 10 (1 tutorial, 4 how-to guides, 2 reference, 3 explanation) |
| fast-digest | [docs](../../gems/digest/docs/) | 11 (1 tutorial, 4 how-to guides, 2 reference, 4 explanation) |
| fast-proxy-status | [docs](../../gems/proxy_status/docs/) | 14 (1 tutorial, 4 how-to guides, 5 reference, 4 explanation) |
| fast-client-cert | [docs](../../gems/client_cert/docs/) | 9 (1 tutorial, 3 how-to guides, 1 reference, 4 explanation) |

Each gem's `documentation_uri` points at its docs tree — also on the RubyGems page of each gem.

The root tree explains the family in plain language. The per-gem trees are the technical layer — terse and RFC-section-cited, engineer to engineer. Every path here descends from one into the other.

## How the family is verified

One command runs every gem's suite: `bundle exec sus` — `config/sus.rb` routes every `gems/*/lib` and `gems/*/test` into the run. fast-sfv is refereed by the vendored official httpwg conformance corpus (see [conformance](../../gems/sfv/docs/reference/conformance.md) — the counts and provenance live there, not here). Every gem carries allocation budgets as tests (see [why allocation budgets](../explanation/why-allocation-budgets.md)). Each gem's [performance page](../../gems/sfv/docs/explanation/performance.md) carries both-mode benchmark tables from one measurement session (the numbers live there, never here). CI runs the spec matrix on Ruby 3.4/4.0, lint, the per-gem `gem build` loop and a security audit (`.github/workflows/ci.yml`). `script/verify-packaged.rb` proves a built gem carries its require path from outside the checkout. Each per-gem api page records how that gem's own surface is verified — linked above, numbers not restated.
