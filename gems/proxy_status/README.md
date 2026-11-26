# fast-proxy-status

fast-proxy-status is the RFC 9209 Proxy-Status implementation for Ruby: the HTTP response field that conveys how intermediaries handled a response, built on fast-sfv.

## What it is

`Fast::ProxyStatus` implements RFC 9209 §2: "Its value is a List (see Section 3.1 of [STRUCTURED-FIELDS]). Each member of the List represents an intermediary that has handled the response. The first member represents the intermediary closest to the origin server, and the last member represents the intermediary closest to the user agent." Each member is a String or Token carrying §2.1's parameters — the five this library reads with typed readers (`error`, `next-hop`, `next-protocol`, `received-status`, `details`) — and the §2.3 proxy error type registry is pinned as frozen data (`Fast::ProxyStatus::ERRORS`), unknown error types passing through untouched.

The lenient parse (`parse`) answers a recipient's view and never raises on field content; the strict parse (`parse!`) tells the truth with byte offsets; `to_s` and construction are always strict; results are frozen value objects; one runtime dependency (fast-sfv), no stdlib, no middleware, no connection state.

Pure Ruby; MIT license; source at `https://github.com/jetpks/fast-http-fields`.

## Installation

```sh
gem install fast-proxy-status
```

In a Gemfile:

```ruby
gem "fast-proxy-status"
```

Require path is `fast/proxy_status`:

```ruby
require "fast/proxy_status"
```

Requires Ruby >= 3.4 and RubyGems >= 3.5.3; the only runtime requirement is fast-sfv.

## Quickstart

Read a response's Proxy-Status and walk the chain of intermediaries:

```ruby
require "fast/proxy_status"

field = Fast::ProxyStatus.parse("revproxy1.example.net, ExampleCDN")
field.first.value  # => "revproxy1.example.net" (closest to the origin server)
field.last.value   # => "ExampleCDN" (closest to the user agent)
```

The error lookup, §2.1.1's 504 example and the registry behind it:

```ruby
field = Fast::ProxyStatus.parse("ExampleCDN; error=connection_timeout")
field.first.error                             # => "connection_timeout"
Fast::ProxyStatus.recommended_status("connection_timeout")  # => 504
Fast::ProxyStatus.response_only?("connection_timeout")      # => true
```

A wrong-typed parameter is diagnostic data, never a field failure (§2.1.5's own quoted-string error example parses):

```ruby
field = Fast::ProxyStatus.parse(%q{proxy.example.net; error="http_protocol_error"})
field.first.error     # => nil (the section 2.1.1 rule: the value is a Token)
field.first["error"]  # => "http_protocol_error" (the raw value, preserved)
```

## The guarantees

`parse` never raises on field content. A field whose syntax is not a Structured Field Value, or whose List carries a member that is not a String or Token, is treated as absent — the entire field ignored (RFC 9651 §2.2), the same empty value an absent field gives. Parameters never fail the field: unknown parameters and known parameters of a type §2.1 does not allow are preserved in the member's data and ignored semantically — the diagnostic leniency a debugging field demands. `parse!` is the strict truth: the first offender in List order raises `Fast::ProxyStatus::ParseError` positioned at the offending value's byte offset; `valid?` mirrors it with a boolean. `to_s` and construction are always strict: a sender never puts garbage on the wire, and the canonical form re-emits round-trip (the RFC's `; error=` spacing canonicalizes to `;error=`).

The value objects are frozen: the field, its `hops` Array, each `Fast::ProxyStatus::Hop` (an `Fast::SFV::Item` — the raw `#[]` and `#params` beside the five typed readers), every parameter Hash and value String. A String is one field value; an Array is the field's lines, combined per RFC 9651 §4.2 (a List concatenates — there is no last-wins).

## Append yourself, the intermediary's operation

§2: "When adding a value to the Proxy-Status field, intermediaries SHOULD preserve the existing members of the field." `append` answers a new frozen value with this intermediary's member as the LAST — closest to the user agent — and re-emits the whole list canonically:

```ruby
field = Fast::ProxyStatus.append("SomeOtherProxy", Fast::SFV::Token.new("ThisProxy"))
field.to_s  # => "SomeOtherProxy, ThisProxy"
```

The upstream value is parsed leniently — nil, a String, an Array of lines, or a held `Fast::ProxyStatus`; a malformed upstream field starts a fresh list rather than failing the response. `TypeError` for a wrong input type, `Fast::ProxyStatus::SerializeError` for a wrong hop or parameter.

## The trailer story: append, then promote

§2 lets an intermediary send Proxy-Status as a trailer field when it has also generated a header field with the same member: the proxy appends itself to the header, then appends its parameters to the trailer. A client MAY promote the trailer into the header — `promote` is §2's algorithm, spec-exact:

```ruby
promoted = Fast::ProxyStatus.promote("SomeOtherProxy, ThisProxy", "ThisProxy; error=read_timeout")
promoted.header.to_s  # => "SomeOtherProxy, ThisProxy;error=read_timeout"
promoted.trailer      # => nil (removed: every member promoted)
```

Each trailer member replaces the leftmost header member that spells the same identifier — String or Token, character by character, parameters ignored — in its entirety; an unmatched member stays in the trailer, and the trailer is removed when nothing remains. The answer is a frozen `Fast::ProxyStatus::Promotion`: `header` is nil exactly when there was no header field, `trailer` exactly when nothing remains.

## The registry as data

`Fast::ProxyStatus::ERRORS` carries §2.3's 32 proxy error types in document order, each with its recommended HTTP status code (an Integer — `http_request_error` and `proxy_internal_response` carry the RFC's own prose), its response-only flag, and its extra parameters. The lookups `registered?`, `recommended_status`, `response_only?` and `extra_parameters` answer unknown names with nil/false. The registry never gates a parse or an emit: an unknown error type parses, emits and round-trips untouched — future registrations never break old gem versions.

## The error hierarchy

`Fast::ProxyStatus::Error` → `ParseError`/`SerializeError`, both carrying `#offset` — the family shape. The wrongness of a parse defect or a value that cannot go on the wire is field content; a wrong input type is a caller bug and raises plain `TypeError`.

## Status

Current release 0.1.0; changelog at [CHANGELOG.md](CHANGELOG.md). This entry of the gem map carries Proxy-Status only (RFC 9209); `Fast::CacheStatus` (RFC 9211) and `Fast::TargetedCacheControl` (RFC 9213) are the next entries — the hop-list plumbing they will sit beside is already here.
