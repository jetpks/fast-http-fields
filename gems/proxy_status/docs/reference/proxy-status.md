# Proxy-Status API reference

The definitive page for the `Fast::ProxyStatus` surface. The registry has its own page (see [The proxy error type registry](proxy-error-types.md)).

## The module

`Fast::ProxyStatus`, required as `require "fast/proxy_status"`; `Fast::ProxyStatus::VERSION` is `"0.1.0"`.

The class includes the shared List engine; the root the other two field classes' error hierarchies descend from.

Ruby >= 3.4, RubyGems >= 3.5.3, exactly one runtime dependency: fast-sfv.

Public surface: the class methods, the instance readers, `Hop`, `Promotion`, the registry functions and the errors. The shared engine `Fast::ProxyStatus::ListField` and its `Member` base are reachable nested constants the two List fields ride, reached through the field classes' surfaces; `Item`, `Token`, `BINARY`, the `Scan` classes, `EMPTY`, `NONE` and `PARAM_RULES` are `private_constant`s.

## Parsing

`Fast::ProxyStatus.parse(input)` → the frozen value object; §2 recipient semantics; never raises on field content — a malformed field or ANY member that is not a String or Token answers the shared frozen empty value (RFC 9651 §2.2); `TypeError` for a non-String/non-Array input.

Parameters never fail the field: unknown and wrong-typed parameters are preserved in the Hop's data and ignored by the typed readers — the lenient parse is the strict walk with the parameter checks not applied, never the strict walk rescued.

`Fast::ProxyStatus.parse!(input)` → the frozen value object, strict: the wrapped List failure, then the member constraint (positioned at the member's identifier) and §2.1's parameter constraints (positioned at the parameter's VALUE, just past the "="; the key's end for the valueless form), the first offender in List order raised.

`Fast::ProxyStatus.valid?(input)` → true/false; never raises.

Input: a String (one field value) or an Array of String field lines, combined with ", " (RFC 9651 §4.2). A List concatenates — there is no last-wins.

## The value object

Readers: `hops` (the frozen Array of Hops in wire order), `first`/`last` (nil when empty), `size`, `empty?`, `each` (yields each Hop), `[](index)` (Array semantics).

`to_s` — the canonical RFC 9651 §4.1.1 List serialization, `""` when none are held; never raises; a parsed value re-emits its canonical form.

`==` / `eql?` — canonical-wire-form equality WITHIN the class; a ProxyStatus never equals a CacheStatus or a String; `hash` consistent.

`inspect` — `#<Fast::ProxyStatus>` when empty, else `#<Fast::ProxyStatus <wire>>`:

```ruby
Fast::ProxyStatus.parse("ExampleCDN; error=connection_timeout").inspect
# => "#<Fast::ProxyStatus ExampleCDN;error=connection_timeout>"
```

Frozen at construction: the field, the hops Array, each Hop, each params Hash, each value String.

## The Hop members

`Fast::ProxyStatus::Hop < Fast::ProxyStatus::ListField::Member` — an `Fast::SFV::Item`: `#value`, `#params`, the canonical `#to_s` inherited; `#[]` the raw parameter view; class-checked canonical equality (a Hop never equals a plain Item or a Cache).

The five typed readers, nil when the parameter is absent or wrong-typed: `error` (§2.1.1 a Token), `next_hop` (§2.1.2 a String or Token), `next_protocol` (§2.1.3 a Token or Byte Sequence — a String tagged ASCII-8BIT), `received_status` (§2.1.4 an Integer), `details` (§2.1.5 a plain String).

The reader set on one fence:

```ruby
hop = Fast::ProxyStatus.parse(
  "cdn.example.org; next-hop=backend.example.org:8001; next-protocol=h2; received-status=200"
).first
hop.next_hop          # => #<Fast::SFV::Token "backend.example.org:8001">
hop.next_protocol     # => #<Fast::SFV::Token "h2">
hop.received_status   # => 200
```

A byte-sequence next-protocol answers the binary String:

```ruby
hop = Fast::ProxyStatus.parse("p; next-protocol=:AAAA:").first
hop.next_protocol             # => "\x00\x00\x00"
hop.next_protocol.encoding    # => #<Encoding:BINARY (ASCII-8BIT)>
hop.next_protocol.bytesize    # => 3
```

## Construction

`Fast::ProxyStatus::Hop.new(value, params = {})` — the identifier a plain String (emits quoted) or a `Fast::SFV::Token` (emits bare); a String tagged ASCII-8BIT is refused (it would emit as a Byte Sequence). `params` a Hash of §2.1 parameters under Structured Fields keys: the five carry their sections' types, any other key any bare Structured Fields type. The value String and the params Hash freeze IN PLACE. `Fast::ProxyStatus.new(members)` — an Array of Hops, each already validated at its own construction.

The emission forms, one fence:

```ruby
hop = Fast::ProxyStatus::Hop.new(Fast::SFV::Token.new("x"),
                                  { "error" => Fast::SFV::Token.new("connection_timeout"),
                                    "received-status" => 502 })
hop.to_s  # => "x;error=connection_timeout;received-status=502"
```

## append

The class form `Fast::ProxyStatus.append(input, member, params = {})` and the instance form `#append(member, params = {})`: the received members preserved in order, this sender's member appended as the LAST, a NEW frozen value; the upstream parsed leniently. TypeError for a wrong input type; SerializeError for a wrong member or parameter.

```ruby
field = Fast::ProxyStatus.append("SomeOtherProxy", Fast::SFV::Token.new("ThisProxy"))
field.to_s  # => "SomeOtherProxy, ThisProxy"
```

## promote and the Promotion

`Fast::ProxyStatus.promote(header, trailer)` — §2's algorithm, spec-exact, both arguments read as `parse` reads them; answers a frozen `Fast::ProxyStatus::Promotion`.

`Promotion#header` — the promoted header value, nil exactly when the header input was nil; `Promotion#trailer` — the unmatched members, nil exactly when nothing remains; class-checked equality on the pair; `inspect` as `#<Fast::ProxyStatus::Promotion header=…, trailer=…>`.

```ruby
promoted = Fast::ProxyStatus.promote("SomeOtherProxy, ThisProxy", "ThisProxy; error=read_timeout")
promoted.header.to_s  # => "SomeOtherProxy, ThisProxy;error=read_timeout"
promoted.trailer      # => nil
```

## Errors

`Fast::ProxyStatus::Error < StandardError` — the gem root; never raised in its own right; one rescue guards the whole gem.

`Fast::ProxyStatus::ParseError < Error` — `ParseError.new(message, offset)`, `#offset`: the byte position in the combined field value of the wrapped List failure, the offending member's identifier, or the offending parameter's VALUE.

`Fast::ProxyStatus::SerializeError < Error` — `SerializeError.new(message, offset)`, `#offset` (0: the checks run before anything is emitted); the whole emit path raises this and never TypeError.

## How the surface is verified

The vectors: RFC 9209's own §2/§2.1/§3 examples as quoted test vectors — the two-intermediary list, the 504/429 examples, the next-hop/next-protocol/received-status examples, §2.1.5's quoted error, the trailer-promotion pair — frozen in the suite (`test/fast/proxy_status/status.rb`, 540 lines; the registry in `test/fast/proxy_status/registry.rb`, 131 lines).

The suite totals at writing: 3273 passed / 5682 assertions at the monorepo root, every gem's suites green together (`bundle exec sus`); the documentation adds no tests. This is the only leaf carrying the suite totals.

## Requirements

Ruby >= 3.4, RubyGems >= 3.5.3, one runtime dependency (fast-sfv).
