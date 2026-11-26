# Why diagnostics preserve unknown members

## The leniency the RFCs demand

Proxy-Status's own rule: "Unrecognised parameters MUST be ignored" — a debugging field cannot demand that every reader know every sender's vocabulary. RFC 9651 §2.2 carries the substrate half: a field whose syntax is not a Structured Field Value is ignored entirely ("When parsing fails, the entire field is ignored"), and "When field-specific constraints are violated, the entire field is also ignored, unless the field definition defines other handling requirements" — neither 9209 nor 9211 defines other handling for members. RFC 9213 §2.1 spells its own field-level rule for the same reason ("that field MUST be ignored by the cache") — with the per-directive SHOULD-NOT-consume refinement.

The registration paths make leniency structural: all three fields have open registries (9209 §2.2/§2.4, 9211 §4, 9213 §2.4's suffix convention) — an old reader meeting a new vocabulary is the normal case, not the error case.

## Preserved, not dropped

The gem's reading: "ignored" is semantic, never destructive. The raw `#[]` and `#params` hold what the wire said beside the typed readers' nils; the field re-emits it:

```ruby
field = Fast::ProxyStatus.parse("ExampleCDN; vendor-x=3, foo;bar=?0")
field.first["vendor-x"]  # => 3
field.last["bar"]        # => false
field.to_s               # => "ExampleCDN;vendor-x=3, foo;bar=?0"
```

The wrong-typed case — §2.1.5's own example is the canonical one: its error value is a quoted String where §2.1.1 says "a Token", and the gem answers nil from the typed reader with the value preserved raw:

```ruby
field = Fast::ProxyStatus.parse(%q{proxy.example.net; error="http_protocol_error"})
field.first.error     # => nil
field.first["error"]  # => "http_protocol_error"
```

The implementation discipline: the lenient parse is the strict walk with the parameter checks not applied — never the strict walk rescued — so a parameter violation can never drop the field while a member violation must.

## What leniency can leak

RFC 9209 §4: "One of the primary security concerns when using Proxy-Status is leaking information that might aid an attacker. For example, information about the intermediary's configuration and backend topology can be exposed, allowing attackers to directly target backend services that are not prepared for high traffic volume or malformed inputs"; "the field's content is not verified; an intermediary can claim certain actions (e.g., sending a request over an encrypted channel) but fail to actually do that".

RFC 9211 §6: "Attackers can use the information in Cache-Status to probe the behavior of the cache (and other components) and infer the activity of those using the cache"; "knowing if a cache has stored a response can help an attacker execute a timing attack on sensitive data"; "exposing the cache key can help an attacker understand modifications to the cache key, which may assist cache poisoning attacks". The mitigation: "the Cache-Status header field can be omitted, only sent when the client is authorized to receive it, or sent with sensitive information (e.g., the key parameter) only when the client is authorized".

Preserving unknown members is what makes the field a diagnostic you can trust on the wire — but the same preservation means everything a sender put there reaches your logs. Deciding what to generate and what to log is the operator's half of the contract (see [Read Cache-Status for monitoring](../how-to-guides/read-cache-status-for-monitoring.md)).

## When to be strict

`parse!` and `valid?` exist for the sender's side and for diagnostics: a field YOU generated that does not round-trip strict is your bug; a field you received that fails strict is upstream's wire defect, positioned by byte offset. See the three [reference pages](../reference/proxy-status.md).
