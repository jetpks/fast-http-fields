# Read Cache-Status for monitoring

## Read the field

RFC 9211 §2: "Its value is a List. Each member of the List represents a cache that has handled the request. The first member represents the cache closest to the origin server, and the last member represents the cache closest to the user (possibly including the user agent's cache itself if it appends a value)" and §3's three-layer example — three field lines, combined per RFC 9651 §4.2, a List concatenates:

```ruby
field = Fast::CacheStatus.parse(
  ["ReverseProxyCache; hit",
   "ForwardProxyCache; fwd=uri-miss; collapsed; stored",
   "BrowserCache; fwd=uri-miss"]
)
field.size  # => 3
```

The absent field, the plain-Hash idiom:

```ruby
response_headers = { "content-type" => "text/html" }
Fast::CacheStatus.parse(response_headers["cache-status"] || "").empty?  # => true
```

## Walk the chain

`caches` (the frozen Array in wire order), `first`/`last` naming §2's two ends, `each`, Array-style `[]`:

```ruby
field = Fast::CacheStatus.parse(["ReverseProxyCache; hit",
                                 "ForwardProxyCache; fwd=uri-miss; collapsed; stored",
                                 "BrowserCache; fwd=uri-miss"])
field.caches.map(&:value)
# => [#<Fast::SFV::Token "ReverseProxyCache">, #<Fast::SFV::Token "ForwardProxyCache">, #<Fast::SFV::Token "BrowserCache">]
field.first.hit    # => true
field[1].stored    # => true
field.last.fwd     # => #<Fast::SFV::Token "uri-miss">
```

The two-layer example with its quoted-String identifier, walked:

```ruby
field = Fast::CacheStatus.parse('OriginCache; hit; ttl=1100, "CDN Company Here"; hit; ttl=545')
field.caches.each do |cache|
  puts "#{cache.value} hit=#{cache.hit.inspect} ttl=#{cache.ttl.inspect}"
end
# prints: OriginCache hit=true ttl=1100
#         CDN Company Here hit=true ttl=545
```

## Read the parameters that matter

The eight typed readers with their sections:

- `hit` — §2.1 Boolean
- `fwd` — §2.2 Token (the fwd value set)
- `fwd-status` — §2.3 Integer
- `ttl` — §2.4 Integer
- `stored` — §2.5 Boolean
- `collapsed` — §2.6 Boolean
- `key` — §2.7 String
- `detail` — §2.8 Token or String

The monitoring-relevant examples:

```ruby
field = Fast::CacheStatus.parse("ExampleCache; hit; ttl=-412")
field.first.ttl  # => -412

field = Fast::CacheStatus.parse('ExampleCache; hit; key="v2/user/1234"')
field.first.key  # => "v2/user/1234"

field = Fast::CacheStatus.parse("ExampleCache; hit; detail=MEMORY")
field.first.detail  # => #<Fast::SFV::Token "MEMORY">
```

`ttl` "may be negative, to indicate staleness"; `detail`'s semantics "are always specific to the cache that sent it"; `fwd-status` "is only meaningful when fwd is present" and "defaults to the status code sent in the response" when absent — a response-level fact the field object never computes, the caller owns it.

## Wrong-typed parameters are data

The leniency: a wrong-typed parameter never fails the field — the typed reader answers nil and the raw value stays in the data:

```ruby
field = Fast::CacheStatus.parse("ExampleCache; fwd=999, Second; hit=\"yes\", Third; ttl=fast")
field.first.fwd          # => nil
field.first["fwd"]       # => 999
field[1].hit             # => nil
field[1]["hit"]          # => "yes"
field.to_s  # => "ExampleCache;fwd=999, Second;hit=\"yes\", Third;ttl=fast"
```

See [Why diagnostics preserve unknown members](../explanation/diagnostic-leniency.md).

## Check what you expect

The hit/fwd exclusivity SHOULD surfaced — "hit" and "fwd" are exclusive; only one of them should appear on each list member" — never gated:

```ruby
Fast::CacheStatus.parse("ExampleCache; hit; fwd=miss").first.hit_and_fwd?      # => true
Fast::CacheStatus.parse("ExampleCache; hit=?0; fwd=miss").first.hit_and_fwd?   # => true
Fast::CacheStatus.parse("ExampleCache; hit").first.hit_and_fwd?                # => false
```

An unregistered fwd Token parses and round-trips — §2.2 defines the values, it does not MUST them on a recipient:

```ruby
field = Fast::CacheStatus.parse("ExampleCache; fwd=network-miss")
field.first.fwd  # => #<Fast::SFV::Token "network-miss">
field.to_s       # => "ExampleCache;fwd=network-miss"
```

## The strict view for diagnostics

`parse!` tells you exactly what is wrong, positioned:

```ruby
begin
  Fast::CacheStatus.parse!("foo; ttl=1.5")
rescue Fast::CacheStatus::ParseError => e
  e.offset   # => 9
  e.message  # => "ttl: the value must be an Integer, received 1.5"
end
```

`Fast::CacheStatus.valid?("foo; ttl=fast")  # => false`. Unknown parameters are valid and preserved on the strict path (`Fast::CacheStatus.parse!("ExampleCache; fwd=uri-miss; vendor=1").first["vendor"]  # => 1`).

## What the field can expose

"Attackers can use the information in Cache-Status to probe the behavior of the cache (and other components) and infer the activity of those using the cache"; "knowing if a cache has stored a response can help an attacker execute a timing attack on sensitive data"; "exposing the cache key can help an attacker understand modifications to the cache key, which may assist cache poisoning attacks". Monitoring pipelines are the "authorized parties" the RFC's mitigation names — the field "can be omitted, only sent when the client is authorized to receive it, or sent with sensitive information (e.g., the key parameter) only when the client is authorized".

See [Why diagnostics preserve unknown members](../explanation/diagnostic-leniency.md) and [Cache-Status API reference](../reference/cache-status.md).
