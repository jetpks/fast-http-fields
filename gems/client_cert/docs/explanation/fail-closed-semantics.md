# Fail-closed: the unauthenticated connection

RFC 9651 §2.2's substrate rule meeting RFC 9440's security story.

## What fail-closed means here

The substrate rule: "When parsing fails, the entire field is ignored (see Section 4.2). Field definitions cannot override this because doing so would preclude handling by generic software; they can only add additional constraints" and "When field-specific constraints are violated, the entire field is also ignored, unless the field definition defines other handling requirements".

What that means for Client-Cert: there is no empty-certificate value object — the wire never carries one — so the ignored field answers **nil**: no certificate, the unauthenticated connection.

For Client-Cert-Chain: the ignored field answers the shared frozen empty value — the same answer an absent field gives; there is NO member-level filtering, a valid certificate beside a bad one drops with the field.

```ruby
require "fast/client_cert"

Fast::ClientCert::Chain.parse(":aGVsbG8=:, 5, :d29ybGQ=:") == Fast::ClientCert::Chain.parse("!!")  # => true
```

## Why "no certificate" is the answer

RFC 9440 §2.4: "Backend origin servers may then use the Client-Cert header field of the request to determine if the connection from the client to the TTRP was mutually authenticated and, if so, the certificate thereby presented by the client. Access control decisions based on the client certificate (or lack thereof) can be conveyed by selecting response content as appropriate or with an HTTP 403 response, if the certificate is deemed unacceptable for the given context". The absence is information — the recipient's policy consumes it.

The singleton rule is fail-closed too: RFC 9440 §2.2's "MUST NOT have a list of values or occur multiple times in a request" reads as a field a recipient cannot read when it arrives list-shaped — the Item grammar fails it, and a field an Array of lines recombines into is the same failure.

The contrast with the chain: RFC 9440 §2.3's "MAY have a list of values or occur multiple times in a request" — the List grammar concatenates the instances (RFC 9651 §4.2's combining for Lists), so the split form is native and whole, never a fall.

## What the strict view is for

`parse!` is the diagnostics door: the wrapped substrate failure with its offset preserved, or the Byte Sequence constraint at the value's first non-OWS byte (Cert), the first offending member's, quote-aware (Chain). It tells the operator WHERE the field went wrong — never what the recipient should conclude; the conclusion is policy.

`valid?` is the boolean mirror of the strict truth — the cheap "should I log this?".

```ruby
require "fast/client_cert"

begin
  Fast::ClientCert::Cert.parse!("5")
rescue Fast::ClientCert::ParseError => e
  e.message  # => "Client-Cert: the value must be a Byte Sequence, received Integer"
  e.offset  # => 0
end

Fast::ClientCert::Cert.valid?("!!")  # => false
```

## The boundary

A wrong input type (nil, 5, a Symbol) is a caller bug, not field content: TypeError, never a fall.

The PEM helpers' `Error` is a usage failure — the field never parsed, nothing was built — so it answers the base class.

The gem's share of the security posture is exactly this — what it cannot read, it does not guess; everything else (trust, sanitization, policy) is the deployment's.

See [Field injection and the trusted path](field-injection-and-trusted-path.md) and [The whole certificate as opaque DER](the-whole-certificate.md).
