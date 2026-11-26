# Why the family parses leniently and emits strictly

Reading a field and writing one are different jobs. A reader meets whatever the world put on the wire — typos, old senders, fields a proxy mangled. A writer controls its own output completely. The family's rule follows: parse as leniently as your field's RFC tells a recipient to; emit only the canonical form, strictly.

## Reading is the recipient's job

Leniency on the read path is not sloppiness. Each field's RFC already defines what a recipient does with input it cannot read, and inventing your own behavior is how interoperability breaks.

The family's five answers, one line each:

- Priority — the defaults (urgency 3, incremental false)
- Digest — the empty value (treated as absent)
- Client-Cert — nil (no certificate)
- Proxy-Status — unknown members and parameters preserved (diagnostic leniency)
- fast-sfv — strict (it IS the grammar)

The rule that generates the field-gems' shared shape, from RFC 9651: "When field-specific constraints are violated, the entire field is also ignored, unless the field definition defines other handling requirements."

No gem raises on field content. The [start-here tutorial](../tutorials/start-here.md) — section "When a field is unreadable" — is the reader's anchor for what this looks like in practice.

## What unreadable means, field by field

Each field makes its own choice, for its own reason:

Priority keeps serving — urgency 3 is a real answer, so a bad field degrades to it. A service that stops because a client sent a malformed priority hint would be worse than one that serves at a default urgency (see [defaults on malformed](../../gems/priority/docs/explanation/defaults-on-malformed.md)).

Digest and Client-Cert fail closed — an integrity claim you cannot read is no claim; a certificate you cannot read is no certificate. Treating them as defaults would be unsafe (for digest: the [README's fail-closed parse](../../gems/digest/README.md); for client-cert: [fail-closed semantics](../../gems/client_cert/docs/explanation/fail-closed-semantics.md)).

Proxy-Status keeps the data — a diagnostics field is most useful half-readable, so unknown members and parameters are preserved, not rejected (see [diagnostic leniency](../../gems/proxy_status/docs/explanation/diagnostic-leniency.md)).

## When you want the truth

`parse!` exists for when you need the truth instead: a sender debugging its own output, a test asserting a field's shape — positioned errors, the byte where the value went wrong:

```ruby
require "fast/digest"
require "fast/client_cert"

begin
  Fast::Digest::ContentDigest.parse!("md5=5")
rescue Fast::Digest::ParseError => e
  e.message  # => "md5: a Content-Digest value is a Byte Sequence: a String tagged Encoding::ASCII_8BIT (got 5)"
end

begin
  Fast::ClientCert::Cert.parse!("5")
rescue Fast::ClientCert::ParseError => e
  e.message  # => "Client-Cert: the value is a Byte Sequence (got Integer)"
end
```

The same error hierarchy in every gem — `Fast::<Name>::Error` branching into `ParseError` and `SerializeError`, both carrying the byte offset.

## Senders never write garbage

`to_s` and construction are strict in every gem — a sender never puts a malformed value on the wire. The canonical form is RFC 9651's serialization, so every gem's output round-trips and every reader sees the same bytes.

The asymmetry is the point: leniency where you have no control, strictness where you have all of it.

## The exception that proves the rule

fast-sfv parses strictly — because it is not a field, it is the grammar. RFC 9651 says the only error handling is to fail the entire operation altogether, precisely so that implementations cannot drift into workarounds. The four field gems inherit that grammar and layer their RFC's leniency on top.

For the technical version: [strictness](../../gems/sfv/docs/explanation/strictness.md). For the family story: [the SFV substrate](the-sfv-substrate.md).
