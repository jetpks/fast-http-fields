# Cache-Status API reference

The definitive page for the `Fast::CacheStatus` surface.

## The module

`Fast::CacheStatus`, loaded by `require "fast/proxy_status"`; includes the shared List engine with this field's member class, empty value and label; every failure descends from `Fast::ProxyStatus::Error`.

## Parsing

`parse` / `parse!` / `valid?` — the same contracts as Proxy-Status's (§2 recipient semantics, RFC 9651 §2.2), with §2.1-§2.8's parameter constraints on the strict path; the first offender in List order raised positioned at the member's identifier or the parameter's VALUE. A List concatenates — no last-wins.

```ruby
field = Fast::CacheStatus.parse("ExampleCache; hit; ttl=376")
field.first.ttl  # => 376

begin
  Fast::CacheStatus.parse!("foo; ttl=1.5")
rescue Fast::CacheStatus::ParseError => e
  e.offset  # => 9
end
```

## The value object

Readers: `caches` (the frozen Array of Caches in wire order — the engine's members ivar, named), `first`/`last`, `size`, `empty?`, `each`, `[]`.

`to_s` — the canonical RFC 9651 §4.1.1 List serialization, `""` when empty; `==`/`eql?`/`hash` canonical within the class (a CacheStatus never equals a ProxyStatus); `inspect` `#<Fast::CacheStatus <wire>>`:

```ruby
Fast::CacheStatus.parse("ExampleCache; hit; ttl=376").inspect
# => "#<Fast::CacheStatus ExampleCache;hit;ttl=376>"
```

## The Cache members

`Fast::CacheStatus::Cache < Fast::ProxyStatus::ListField::Member` — an `Fast::SFV::Item` with the raw readers, plus the eight typed readers, nil when absent or wrong-typed: `hit`, `fwd`, `fwd_status`, `ttl`, `stored`, `collapsed`, `key`, `detail` — one per §2.1-§2.8.

`hit_and_fwd?` — §2.1's exclusivity SHOULD surfaced, never a gate.

The reader set on one fence:

```ruby
cache = Fast::CacheStatus.parse(
  'c; hit; fwd=miss; fwd-status=304; ttl=1100; stored; collapsed; key="k"; detail="d"'
).first
cache.hit          # => true
cache.fwd          # => #<Fast::SFV::Token "miss">
cache.fwd_status   # => 304
cache.ttl          # => 1100
cache.stored       # => true
cache.collapsed    # => true
cache.key          # => "k"
cache.detail       # => "d"
```

## Construction

`Fast::CacheStatus::Cache.new(value, params = {})` — the identifier a plain String or Token; the eight parameters carry their sections' types, any other key any bare Structured Fields type; then §2.2's emit-side enum check — the ONLY field-specific rule construction adds: a fwd Token outside the defined set raises SerializeError naming the set. `Fast::CacheStatus.new(members)` — an Array of Caches.

The refuse example:

```ruby
begin
  Fast::CacheStatus::Cache.new(Fast::SFV::Token.new("x"), { "fwd" => Fast::SFV::Token.new("weird") })
rescue Fast::CacheStatus::SerializeError => e
  e.message  # => "fwd: the value is a Token of the 2.2 set (bypass, method, uri-miss, vary-miss, miss, request, stale, partial)"
end
```

## append

The class and instance forms as Proxy-Status's, this cache's member appended as the LAST (§2's "caches SHOULD preserve the existing field value").

```ruby
field = Fast::CacheStatus.append(
  'OriginCache; hit; ttl=1100, "CDN Company Here"; hit; ttl=545',
  Fast::SFV::Token.new("MyCache"),
  { "fwd" => Fast::SFV::Token.new("miss") }
)
field.to_s
# => "OriginCache;hit;ttl=1100, \"CDN Company Here\";hit;ttl=545, MyCache;fwd=miss"
```

## The parameter tables

`Fast::CacheStatus::PARAMETERS` — §2.1-§2.8's eight parameters, key => the type its section states, frozen public data.

`Fast::CacheStatus::FWD` — §2.2's eight fwd values in document order, "from most specific to least":

```ruby
Fast::CacheStatus::FWD
# => ["bypass", "method", "uri-miss", "vary-miss", "miss", "request", "stale", "partial"]
```

Both as data, their lookups never gating a parse.

## Errors

`Fast::CacheStatus::Error < Fast::ProxyStatus::Error`, nesting its own `ParseError`/`SerializeError`, both with `#offset`. One rescue on `Fast::ProxyStatus::Error` guards the whole gem.

## Requirements

As Proxy-Status's (the one gem, the one runtime dependency).
