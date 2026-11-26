# Your first diagnostics fields

You will read and write the RFC 9209, 9211 and 9213 diagnostics fields with `Fast::ProxyStatus`, `Fast::CacheStatus` and `Fast::TargetedCacheControl` in about fifteen minutes.

## What you will learn

- Parse a Proxy-Status and walk the chain of intermediaries; read an error and its registry entry; append your own proxy; read a Cache-Status; read a CDN-Cache-Control; know what a malformed field answers and meet the strict error.
- Assumes Ruby >= 3.4 and familiarity with HTTP request/response basics.

## Set up

```sh
gem install fast-proxy-status
```

```ruby
require "fast/proxy_status"
```

## Parse a Proxy-Status field

RFC 9209 §2: "Its value is a List (see Section 3.1 of [STRUCTURED-FIELDS]). Each member of the List represents an intermediary that has handled the response. The first member represents the intermediary closest to the origin server, and the last member represents the intermediary closest to the user agent". §2's own example and its explanation:

```ruby
field = Fast::ProxyStatus.parse("revproxy1.example.net, ExampleCDN")
field.size                     # => 2
field.first.value              # => #<Fast::SFV::Token "revproxy1.example.net">
field.last.value               # => #<Fast::SFV::Token "ExampleCDN">
field.to_s                     # => "revproxy1.example.net, ExampleCDN"
```

Each member is a String or Token, and a Token equals the String that spells it — the class is the wire-type tag.

## Read the error and its registry entry

RFC 9209 §2.1.1's example pair:

```ruby
field = Fast::ProxyStatus.parse("r34.example.net; error=http_request_error, ExampleCDN")
field.first.value      # => #<Fast::SFV::Token "r34.example.net">
field.last.value       # => #<Fast::SFV::Token "ExampleCDN">
field.first.error      # => #<Fast::SFV::Token "http_request_error">
```

The registry behind it:

```ruby
Fast::ProxyStatus.recommended_status("http_request_error")
# => "The applicable 4xx status code"
```

The other four §2.1 parameters on one hop:

```ruby
hop = Fast::ProxyStatus.parse(
  "cdn.example.org; next-hop=backend.example.org:8001; next-protocol=h2; received-status=200"
).first
hop.next_hop          # => #<Fast::SFV::Token "backend.example.org:8001">
hop.next_protocol     # => #<Fast::SFV::Token "h2">
hop.received_status   # => 200
```

`next-hop` is §2.1.2's String-or-Token, `next-protocol` §2.1.3's Token-or-Byte-Sequence, `received-status` §2.1.4's Integer, `details` §2.1.5's String.

The wrong-typed parameter as data, §2.1.5's own example:

```ruby
field = Fast::ProxyStatus.parse(%q{proxy.example.net; error="http_protocol_error"})
field.first.error     # => nil
field.first["error"]  # => "http_protocol_error"
```

See [The proxy error type registry](../reference/proxy-error-types.md).

## Append your own proxy

§2's append-yourself SHOULD — "When adding a value to the Proxy-Status field, intermediaries SHOULD preserve the existing members of the field to allow debugging of the entire chain of intermediaries handling the request unless explicitly configured to remove them":

```ruby
field = Fast::ProxyStatus.append("SomeOtherProxy", Fast::SFV::Token.new("ThisProxy"))
field.to_s  # => "SomeOtherProxy, ThisProxy"
```

The member is a plain String (emits quoted) or a `Fast::SFV::Token` (emits bare) — the class is the wire-type tag.

See [Append your proxy to Proxy-Status](../how-to-guides/append-yourself-to-proxy-status.md).

## Read a Cache-Status field

RFC 9211 §2's List of caches — "the first member represents the cache closest to the origin server, and the last member represents the cache closest to the user (possibly including the user agent's cache itself if it appends a value)" — and §3's three-layer example, combined per RFC 9651 §4.2 — a List concatenates:

```ruby
field = Fast::CacheStatus.parse(
  ["ReverseProxyCache; hit",
   "ForwardProxyCache; fwd=uri-miss; collapsed; stored",
   "BrowserCache; fwd=uri-miss"]
)
field.size  # => 3
```

The typed readers, §3's own failed-collapse example:

```ruby
field = Fast::CacheStatus.parse("ExampleCache; fwd=uri-miss; collapsed=?0")
field.first.fwd        # => #<Fast::SFV::Token "uri-miss">
field.first.collapsed  # => false
field.first.ttl        # => nil
```

`false` is a value (the collapse was attempted and failed), never an absence; the eight readers and their sections live in the reference page.

See [Cache-Status API reference](../reference/cache-status.md) and [Read Cache-Status for monitoring](../how-to-guides/read-cache-status-for-monitoring.md).

## Read a CDN-Cache-Control field

RFC 9213 §2.1's mapping — "cache directives that have no value will be mapped to a Boolean … When the value is a quoted-string, it will be mapped to a String … , and when it is a token, it will map to a Token … , an Integer … , or a Decimal … , depending on the content of the value" — and §2's example `CDN-Cache-Control: max-age=60`:

```ruby
field = Fast::TargetedCacheControl.parse("max-age=600")
field["max-age"]  # => 600
field.to_s        # => "max-age=600"
```

The inference set on one fence, and the flagged leniency:

```ruby
inference = Fast::TargetedCacheControl.parse(%q{no-store, private="Foo, Bar", x-thing=foo, y=1.5})
inference["no-store"]  # => true
inference["private"]   # => "Foo, Bar"
inference["x-thing"]   # => #<Fast::SFV::Token "foo">
inference["y"]         # => 1.5

field = Fast::TargetedCacheControl.parse("max-age=60.5")
field["max-age"]  # => 60.5
field.violating   # => ["max-age"]
```

A violating value is held and flagged — "Implementations SHOULD NOT consume values that violate these inferred constraints" — the caller decides.

See [Emit CDN-Cache-Control](../how-to-guides/emit-cdn-cache-control.md) and [Targeted cache control and the age penalty](../explanation/age-penalty.md).

## When the field is wrong

`parse` never raises on field content: malformed input or any member that is not a String or Token answers the shared frozen EMPTY value — the same answer an absent field gives:

```ruby
Fast::ProxyStatus.parse("!!").empty?          # => true
Fast::ProxyStatus.parse("ExampleCDN, 5").to_s # => ""
Fast::CacheStatus.parse("!!").to_s            # => ""
Fast::TargetedCacheControl.parse("!!").to_s   # => ""
```

`parse!` is the strict view: it raises the field's `ParseError` with `#offset`, the byte position in the combined field value:

```ruby
begin
  Fast::ProxyStatus.parse!("foo; error=5")
rescue Fast::ProxyStatus::ParseError => e
  e.offset  # => 11
end
```

`Fast::CacheStatus.valid?("foo; ttl=fast")  # => false` when you only need a yes/no.

See [Why diagnostics preserve unknown members](../explanation/diagnostic-leniency.md).

## Where next

- [Append your proxy to Proxy-Status](../how-to-guides/append-yourself-to-proxy-status.md)
- [Promote a Proxy-Status trailer into the header](../how-to-guides/promote-a-proxy-status-trailer.md)
- [Read Cache-Status for monitoring](../how-to-guides/read-cache-status-for-monitoring.md)
- [Emit CDN-Cache-Control](../how-to-guides/emit-cdn-cache-control.md)
- [Proxy-Status API reference](../reference/proxy-status.md)
- [Cache-Status API reference](../reference/cache-status.md)
- [Targeted Cache Control API reference](../reference/targeted-cache-control.md)
- [The proxy error type registry](../reference/proxy-error-types.md)
- [The cache directive table](../reference/cache-directives.md)
