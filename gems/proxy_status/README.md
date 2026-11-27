# fast-proxy-status

fast-proxy-status is the RFC 9209, 9211 and 9213 diagnostics-field implementation for Ruby: Proxy-Status, Cache-Status and Targeted Cache Control, built on fast-sfv.

## What it is

`Fast::ProxyStatus` implements RFC 9209 §2 — "Its value is a List (see Section 3.1 of [STRUCTURED-FIELDS]). Each member of the List represents an intermediary that has handled the response. The first member represents the intermediary closest to the origin server, and the last member represents the intermediary closest to the user agent" — each member a String or Token carrying §2.1's five parameters as typed readers (`error`, `next-hop`, `next-protocol`, `received-status`, `details`), with §2.3's proxy error type registry pinned as frozen data (`Fast::ProxyStatus::ERRORS`), unknown error types passing through untouched.

`Fast::CacheStatus` implements RFC 9211 §2 — the same List shape, one member per cache, "the first member represents the cache closest to the origin server, and the last member represents the cache closest to the user (possibly including the user agent's cache itself if it appends a value)" — with the eight §2.1-§2.8 parameters as typed readers (`hit`, `fwd`, `fwd-status`, `ttl`, `stored`, `collapsed`, `key`, `detail`) and §2.2's fwd value set pinned as frozen data (`Fast::CacheStatus::FWD`).

`Fast::TargetedCacheControl` implements RFC 9213 — the targeted cache-control fields as a Dictionary of cache directives with §2.1's type-inference rules, the known-directive table pinned as frozen data (`Fast::TargetedCacheControl::DIRECTIVES`), and a violating directive preserved-but-flagged on parse.

The shared mechanics: the lenient parse (`parse`) answers a recipient's view and never raises on field content; the strict parse (`parse!`) tells the truth with byte offsets; `to_s` and construction are always strict; results are frozen value objects; one runtime dependency (fast-sfv), no stdlib, no middleware, no connection state. The two List fields share one engine, `Fast::ProxyStatus::ListField`.

Pure Ruby; MIT license; source at `https://github.com/jetpks/fast-http-fields`.

## Installation

```sh
gem install fast-proxy-status
```

In a Gemfile:

```ruby
gem "fast-proxy-status"
```

```ruby
require "fast/proxy_status"
```

Requires Ruby >= 3.4 and RubyGems >= 3.5.3; the only runtime requirement is fast-sfv.

## Quickstart: Proxy-Status

Read a response's Proxy-Status and walk the chain of intermediaries:

```ruby
require "fast/proxy_status"

field = Fast::ProxyStatus.parse("revproxy1.example.net, ExampleCDN")
field.first.value == "revproxy1.example.net"  # => true
field.last.value == "ExampleCDN"              # => true
```

`first` is the intermediary closest to the origin server and `last` the one closest to the user agent; the member values are `Fast::SFV::Token`s — a String that equals it spells it.

The error lookup, §2.1.1's 504 example and the registry behind it:

```ruby
field = Fast::ProxyStatus.parse("ExampleCDN; error=connection_timeout")
field.first.error                                          # => #<Fast::SFV::Token "connection_timeout">
Fast::ProxyStatus.recommended_status("connection_timeout") # => 504
Fast::ProxyStatus.response_only?("connection_timeout")     # => true
```

A wrong-typed parameter is diagnostic data, never a field failure (§2.1.5's own quoted-string error example parses):

```ruby
field = Fast::ProxyStatus.parse(%q{proxy.example.net; error="http_protocol_error"})
field.first.error     # => nil
field.first["error"]  # => "http_protocol_error"
```

See the [tutorial](docs/tutorials/diagnostics-fields.md) for the guided path.

## Cache-Status: how the caches handled the response

RFC 9211 §3's three-layer example — three field lines, combined per RFC 9651 §4.2 (a List concatenates):

```ruby
field = Fast::CacheStatus.parse(
  ["ReverseProxyCache; hit",
   "ForwardProxyCache; fwd=uri-miss; collapsed; stored",
   "BrowserCache; fwd=uri-miss"]
)
field.size  # => 3
field.to_s  # => "ReverseProxyCache;hit, ForwardProxyCache;fwd=uri-miss;collapsed;stored, BrowserCache;fwd=uri-miss"
```

The three-line example's members read through the typed readers — `false` is a value, never an absence (§3's own `collapsed=?0` example):

```ruby
field = Fast::CacheStatus.parse("ExampleCache; fwd=uri-miss; collapsed=?0")
field.first.fwd        # => #<Fast::SFV::Token "uri-miss">
field.first.collapsed  # => false
field.first.ttl        # => nil
```

The hit/fwd exclusivity is §2.1's SHOULD — "hit" and "fwd" are exclusive; only one of them should appear on each list member" — surfaced, never gated: `hit_and_fwd?` answers true exactly when a member carries both, and the field still parses, validates and round-trips:

```ruby
field = Fast::CacheStatus.parse("ExampleCache; hit; fwd=miss")
field.first.hit_and_fwd?  # => true
```

The fwd value set is §2.2's own: `Fast::CacheStatus::FWD` pins the eight defined reasons, from most specific to least. The set is validated on emit only — §2.2 defines the values, it does not MUST them on a recipient — so an unregistered Token parses and round-trips untouched, while `Cache.new` refuses one:

```ruby
Fast::CacheStatus.parse("ExampleCache; fwd=network-miss").first.fwd
# => #<Fast::SFV::Token "network-miss">

Fast::CacheStatus::FWD
# => ["bypass", "method", "uri-miss", "vary-miss", "miss", "request", "stale", "partial"]
```

A cache appends itself as the LAST member — §2's "caches SHOULD preserve the existing field value" — the received members kept in order, the answer a new frozen value:

```ruby
field = Fast::CacheStatus.append(
  'OriginCache; hit; ttl=1100, "CDN Company Here"; hit; ttl=545',
  Fast::SFV::Token.new("MyCache"),
  { "fwd" => Fast::SFV::Token.new("miss") }
)
field.to_s
# => "OriginCache;hit;ttl=1100, \"CDN Company Here\";hit;ttl=545, MyCache;fwd=miss"
```

See the [monitoring how-to](docs/how-to-guides/read-cache-status-for-monitoring.md) and the [Cache-Status reference](docs/reference/cache-status.md).

## Targeted Cache Control: directives aimed at one class of cache

RFC 9213's targeted fields are Dictionaries of cache directives — "a targeted field is an HTTP response header field that has the same semantics as the Cache-Control response header field ([HTTP-CACHING], Section 5.2). However, it has a distinct field name that indicates the target for its cache directives" — their values mapped into Structured Fields types by §2.1. The registered instance is `Fast::TargetedCacheControl::FIELD_NAME` ("CDN-Cache-Control", §3), and the five directives §2.2 MUSTs are pinned as frozen data in `DIRECTIVES` with unknown directives passing through untouched:

```ruby
field = Fast::TargetedCacheControl.parse("max-age=600")
field["max-age"]  # => 600
field.to_s        # => "max-age=600"

inference = Fast::TargetedCacheControl.parse(%q{no-store, private="Foo, Bar", x-thing=foo, y=1.5})
inference["no-store"]  # => true
inference["private"]   # => "Foo, Bar"
inference["x-thing"]   # => #<Fast::SFV::Token "foo">
inference["y"]         # => 1.5
```

The leniency is §2.1's own split, and it is the module's design core: an empty field or a parsing error is the entire field ignored — "that field MUST be ignored by the cache" — while a directive whose value violates the inferred constraints is PRESERVED and FLAGGED, because "Implementations SHOULD NOT consume values that violate these inferred constraints": `#violating` answers the SHOULD-NOT-consume set, the value stays in the data, and the field still round-trips:

```ruby
field = Fast::TargetedCacheControl.parse("max-age=60.5")
field["max-age"]  # => 60.5
field.violating   # => ["max-age"]
field.to_s        # => "max-age=60.5"
```

Emit is always strict — §2.1: "Implementations MUST NOT generate values that violate these inferred constraints" — every value one of the five inferred types, a known directive carrying its section's type, keys Structured Fields keys. §2.1's digit-initial rule holds structurally: a plain String always emits quoted, and a Token's own grammar refuses the form at its construction, so a string whose first character is not alphabetic or `*` can never be mistaken for another type:

```ruby
Fast::TargetedCacheControl.new({ "max-age" => 600, "no-store" => true }).to_s
# => "max-age=600, no-store"

Fast::TargetedCacheControl.new({ "x-custom" => "9abc" }).to_s  # => "x-custom=\"9abc\""
```

See the [emitting how-to](docs/how-to-guides/emit-cdn-cache-control.md) and the [Targeted Cache Control reference](docs/reference/targeted-cache-control.md).

## The guarantees

`parse` never raises on field content. A field whose syntax is not a Structured Field Value, or whose List carries a member that is not a String or Token, is treated as absent — the entire field ignored (RFC 9651 §2.2: "When field-specific constraints are violated, the entire field is also ignored, unless the field definition defines other handling requirements"), the same shared frozen empty value an absent field gives. Parameters never fail the field: unknown parameters and known parameters of a type the field's own sections do not allow are preserved in the member's data and ignored semantically — the diagnostic leniency a debugging field demands. The TargetedCacheControl split is the one exception that is not a failure: a violating directive is preserved and flagged, the rest of the field stays readable. `parse!` is the strict truth: the first offender in List or Dictionary order raises `Fast::ProxyStatus::ParseError` (or the field's own, descending from it) positioned at the offending value's byte offset; `valid?` mirrors it with a boolean. `to_s` and construction are always strict: a sender never puts garbage on the wire, and the canonical form re-emits round-trip (the RFC's `; hit=` spacing canonicalizes to `;hit=`).

The value objects are frozen: the field, its `hops`/`caches` Array or `members` Hash, each member (an `Fast::SFV::Item` — the raw `#[]` and `#params` beside the typed readers), every parameter Hash and value String. A String is one field value; an Array is the field's lines, combined per RFC 9651 §4.2 — "parsers MUST combine all field lines in the same section (header or trailer) that case-insensitively match the field name into one comma-separated field-value" — a List concatenates (there is no last-wins); a Dictionary keeps the last value under the first position.

See [Why diagnostics preserve unknown members](docs/explanation/diagnostic-leniency.md).

## Append yourself, the intermediary's operation

§2's "When adding a value to the Proxy-Status field, intermediaries SHOULD preserve the existing members of the field to allow debugging of the entire chain of intermediaries handling the request unless explicitly configured to remove them". `append` answers a new frozen value with this intermediary's member as the LAST — closest to the user agent — and re-emits the whole list canonically:

```ruby
field = Fast::ProxyStatus.append("SomeOtherProxy", Fast::SFV::Token.new("ThisProxy"))
field.to_s  # => "SomeOtherProxy, ThisProxy"
```

The upstream value is parsed leniently — nil, a String, an Array of lines, or a held `Fast::ProxyStatus`; a malformed upstream field starts a fresh list rather than failing the response. `TypeError` for a wrong input type, `Fast::ProxyStatus::SerializeError` for a wrong hop or parameter. `Fast::CacheStatus.append` is the same operation for a cache, with §2.2's fwd set validated at the construction boundary.

See [Append your proxy to Proxy-Status](docs/how-to-guides/append-yourself-to-proxy-status.md).

## The trailer story: append, then promote

§2 lets an intermediary send Proxy-Status as a trailer field when it has also generated a header field with the same member — "an intermediary MUST NOT send Proxy-Status as a trailer field unless it has also generated a Proxy-Status header field with the same member (although potentially different parameters) in that message" — the proxy appends itself to the header, then appends its parameters to the trailer. A client MAY promote the trailer into the header — `promote` is §2's algorithm, spec-exact:

```ruby
promoted = Fast::ProxyStatus.promote("SomeOtherProxy, ThisProxy", "ThisProxy; error=read_timeout")
promoted.header.to_s  # => "SomeOtherProxy, ThisProxy;error=read_timeout"
promoted.trailer      # => nil
```

Each trailer member replaces the leftmost header member that spells the same identifier — String or Token, character by character, parameters ignored — in its entirety; an unmatched member stays in the trailer, and the trailer is removed when nothing remains. The answer is a frozen `Fast::ProxyStatus::Promotion`: `header` is nil exactly when there was no header field, `trailer` exactly when nothing remains.

See [Promote a Proxy-Status trailer into the header](docs/how-to-guides/promote-a-proxy-status-trailer.md).

## The registry as data

`Fast::ProxyStatus::ERRORS` carries §2.3's 32 proxy error types in document order, each with its recommended HTTP status code (an Integer — `http_request_error` and `proxy_internal_response` carry the RFC's own prose), its response-only flag, and its extra parameters. The lookups `registered?`, `recommended_status`, `response_only?` and `extra_parameters` answer unknown names with nil/false. The registry never gates a parse or an emit: an unknown error type parses, emits and round-trips untouched — future registrations never break old gem versions. The same rule holds for the two newer tables: `Fast::CacheStatus::PARAMETERS`/`FWD` and `Fast::TargetedCacheControl::DIRECTIVES` never gate a parse.

See [The proxy error type registry](docs/reference/proxy-error-types.md), [The cache directive table](docs/reference/cache-directives.md), and [Why diagnostics preserve unknown members](docs/explanation/diagnostic-leniency.md).

## The error hierarchy

`Fast::ProxyStatus::Error` is the gem root, and the two newer modules descend from it — `Fast::CacheStatus::Error` and `Fast::TargetedCacheControl::Error`, each nesting its own `ParseError`/`SerializeError` — so one rescue guards the whole gem, both with `#offset`. The wrongness of a parse defect or a value that cannot go on the wire is field content; a wrong input type is a caller bug and raises plain `TypeError`.

See the three [reference pages](docs/reference/proxy-status.md).

## Documentation

- Tutorial: [Your first diagnostics fields](docs/tutorials/diagnostics-fields.md) — one guided path across all three modules.
- How-to guides:
  - [Append your proxy to Proxy-Status](docs/how-to-guides/append-yourself-to-proxy-status.md) — the intermediary's operation.
  - [Promote a Proxy-Status trailer into the header](docs/how-to-guides/promote-a-proxy-status-trailer.md) — the client's operation.
  - [Read Cache-Status for monitoring](docs/how-to-guides/read-cache-status-for-monitoring.md) — combine field lines and read the typed parameters.
  - [Emit CDN-Cache-Control](docs/how-to-guides/emit-cdn-cache-control.md) — construct the Dictionary and handle the leniency.
- Reference:
  - [Proxy-Status API reference](docs/reference/proxy-status.md) — the complete `Fast::ProxyStatus` surface.
  - [Cache-Status API reference](docs/reference/cache-status.md) — the complete `Fast::CacheStatus` surface.
  - [Targeted Cache Control API reference](docs/reference/targeted-cache-control.md) — the complete `Fast::TargetedCacheControl` surface.
  - [The proxy error type registry](docs/reference/proxy-error-types.md) — RFC 9209 §2.3's 32 entries as data.
  - [The cache directive table](docs/reference/cache-directives.md) — the five §2.2 MUST-implement directives.
- Explanation:
  - [Why diagnostics preserve unknown members](docs/explanation/diagnostic-leniency.md) — the RFCs' leniency rules.
  - [Targeted cache control and the age penalty](docs/explanation/age-penalty.md) — RFC 9213 §2.3's freshness interaction.
  - [The Targeted Cache Control boundary](docs/explanation/the-targeted-cache-control-boundary.md) — what this class does not parse.
  - [Performance and allocation budgets](docs/explanation/performance.md) — how the paths stay allocation-lean.

Current release 0.1.1; changelog at [CHANGELOG.md](CHANGELOG.md).
