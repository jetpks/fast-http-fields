# Why the registries are data, not rules

HTTP field specs pin registries — named sets the field's values draw from: 32 proxy error types, 8 hash algorithms, 8 cache freshness reasons, 5 targeted cache directives. A library could enforce them as validation rules. The family pins them as frozen data instead, and the difference is the gem's behavior on the day the registry grows.

## The registries the family carries

The field specs each define a registry that grows over time through IANA registration. The family carries frozen snapshots of them:

Proxy-Status error types with the HTTP status each recommends — 32 entries, the diagnostics the path reports (see [proxy error types](../../gems/proxy_status/docs/reference/proxy-error-types.md)).

Digest hash algorithms with their Active and Deprecated statuses — 8 entries, the checksums a field may carry (see [algorithms](../../gems/digest/docs/reference/algorithms.md)).

Cache-Status parameters and fwd reasons — 8 parameters and 8 forwarding reasons, the cache's accounting (see [cache-status](../../gems/proxy_status/docs/reference/cache-status.md)).

Targeted Cache Control's directive type inference — 5 directives, the CDN-Cache-Control vocabulary (see [cache directives](../../gems/proxy_status/docs/reference/cache-directives.md)).

The statuses are advisory — an aid to implementation selection, not a rule the parse enforces.

## Unknown values pass through

```ruby
require "fast/digest"
require "fast/proxy_status"

Fast::Digest::ALGORITHMS.keys  # => ["sha-512", "sha-256", "md5", "sha", "unixsum", "unixcksum", "adler", "crc32c"]
Fast::ProxyStatus::ERRORS.size  # => 32
Fast::ProxyStatus.recommended_status("cdn_reset")  # => nil
Fast::Digest::ContentDigest.parse("future-alg=:AAAA:").keys  # => ["future-alg"]
```

These registries live at IANA and grow by registration, without a new RFC revision. A gem version frozen today will meet fields registered tomorrow, and it must still read them.

An unknown error type still parses, round-trips and lands in your monitoring — a lookup answers nil, never an exception. An unknown hash algorithm still carries its digest bytes bytewise. Old gem versions never break on new registrations — the parse is not the registry's gate.

## Where the data ends and the rules begin

The registries never gate a parse, but every gem still validates hard where the RFC demands it. The field's own type constraints apply — a digest member is a byte sequence; a preference value is an integer 0 through 10 — and the sender's side is strict everywhere. Construction and emit check types and, where the RFC defines a closed set a sender draws from, the set — the Cache-Status fwd values at emit, for example.

The rule of thumb: data on the read path, rules on the write path — the lenient-parse, strict-emit principle applied to registries (see [why lenient-parse, strict-emit](why-lenient-parse-strict-emit.md)).

## Where each registry lives

- Proxy error types: [proxy error types](../../gems/proxy_status/docs/reference/proxy-error-types.md)
- Digest algorithms: [algorithms](../../gems/digest/docs/reference/algorithms.md)
- Cache-Status parameters and fwd values: [cache-status](../../gems/proxy_status/docs/reference/cache-status.md)
- Targeted Cache Control directives: [cache directives](../../gems/proxy_status/docs/reference/cache-directives.md)

The tables, their counts, their pinning method and their lookups are documented there in full.
