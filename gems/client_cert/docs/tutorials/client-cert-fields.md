# Your first Client-Cert field

You will read and write RFC 9440's two fields with `Fast::ClientCert` in about ten minutes.

## What you will learn

- Parse a Client-Cert field and check the certificate's DER bytes; parse the chain and split it; convert a PEM block to a field value; know what a malformed field answers and meet the strict error.
- Assumes Ruby >= 3.4 and familiarity with HTTP request basics.

## Set up

```sh
gem install fast-client-cert
```

```ruby
require "fast/client_cert"
```

## Parse a Client-Cert field

RFC 9440 §2.2 makes the TLS client certificate available to the backend application: "Client-Cert is a Byte Sequence with the value of the header encoded as described in Section 2.1", the DER bytes base64-coded between colons. A singleton: "MUST NOT have a list of values or occur multiple times in a request" — the Item grammar enforces it.

The examples use a 5-byte stand-in value so the fences stay readable; real certificates are hundreds of bytes and arrive the same way — the next section brings one.

```ruby
require "fast/client_cert"

cert = Fast::ClientCert::Cert.parse(":aGVsbG8=:")
cert.der                    # => "hello"
cert.der.encoding == Encoding::ASCII_8BIT  # => true
cert.to_s                   # => ":aGVsbG8=:"
```

A Byte Sequence is a String tagged ASCII-8BIT — the encoding IS the wire-type tag (RFC 9651 §3.3.5: "a Byte Sequence is delimited with colons and encoded using base64"), so a UTF-8 String is a different wire type, not a looser one.

The parse discards the OWS around the value (RFC 9651 §4.2's step 2 discards the leading SP before the item parse):

```ruby
require "fast/client_cert"

Fast::ClientCert::Cert.parse(" :aGVsbG8=:  ").der  # => "hello"
```

See [The whole certificate as opaque DER](../explanation/the-whole-certificate.md) for what the bytes carry.

## Verify the bytes

The RFC's own Appendix A certificate — the Figure 1 first block:

```ruby
require "fast/client_cert"
require "digest"

pem = <<~PEM
  -----BEGIN CERTIFICATE-----
  MIIBqDCCAU6gAwIBAgIBBzAKBggqhkjOPQQDAjA6MRswGQYDVQQKDBJMZXQncyBB
  dXRoZW50aWNhdGUxGzAZBgNVBAMMEkxBIEludGVybWVkaWF0ZSBDQTAeFw0yMDAx
  MTQyMjU1MzNaFw0yMTAxMjMyMjU1MzNaMA0xCzAJBgNVBAMMAkJDMFkwEwYHKoZI
  zj0CAQYIKoZIzj0DAQcDQgAE8YnXXfaUgmnMtOXU/IncWalRhebrXmckC8vdgJ1p
  5Be5F/3YC8OthxM4+k1M6aEAEFcGzkJiNy6J84y7uzo9M6NyMHAwCQYDVR0TBAIw
  ADAfBgNVHSMEGDAWgBRm3WjLa38lbEYCuiCPct0ZaSED2DAOBgNVHQ8BAf8EBAMC
  BsAwEwYDVR0lBAwwCgYIKwYBBQUHAwIwHQYDVR0RAQH/BBMwEYEPYmRjQGV4YW1w
  bGUuY29tMAoGCCqGSM49BAMCA0gAMEUCIBHda/r1vaL6G3VliL4/Di6YK0Q6bMje
  SkC3dFCOOB8TAiEAx/kHSB4urmiZ0NX5r5XarmPk0wmuydBVoU4hBVZ1yhk=
  -----END CERTIFICATE-----
PEM

cert = Fast::ClientCert::Cert.parse(Fast::ClientCert.pem_to_field(pem))
cert.der.bytesize  # => 428
Digest::SHA256.hexdigest(cert.der)
# => "bfaf1f7e070f9fa8dd62905f158da73f84a1136624fbafcc9393c8f7287a69eb"
```

`der` answers the bare DER bytes — bytewise comparable from day one (`cert.der == File.binread` of the certificate file, or any digest of the bytes the caller trusts). The gem never inspects them; what the bytes mean is [The whole certificate as opaque DER](../explanation/the-whole-certificate.md)'s story.

See [Validate a Client-Cert at the origin](../how-to-guides/validate-a-client-cert-at-the-origin.md) for the origin-side validation.

## Parse the chain

RFC 9440 §2.3: "the certificate chain used for validation of the end-entity certificate" — a List of Byte Sequences, "The order is the same as the ordering in TLS". The split form is native: "it might be advantageous to split lists into multiple instances".

```ruby
require "fast/client_cert"

chain = Fast::ClientCert::Chain.parse(":aGVsbG8=:, :d29ybGQ=:")
chain.ders    # => ["hello", "world"]
chain.size    # => 2
chain.each.to_a.size  # => 2

lines = chain.split(1)
lines                                  # => [":aGVsbG8=:", ":d29ybGQ=:"]
Fast::ClientCert::Chain.parse(lines) == chain  # => true
```

The chain "does not itself include the end-entity certificate" and "Client-Cert-Chain MUST NOT appear unless Client-Cert is also present" — request-level policies the RFC states and the gem leaves to the caller.

See [Insert Client-Cert and Client-Cert-Chain into forwarded requests](../how-to-guides/insert-the-fields-into-forwarded-requests.md).

## When the field is wrong

`parse` never raises on field content — malformed input answers nil for Client-Cert:

```ruby
require "fast/client_cert"

Fast::ClientCert::Cert.parse("!!").nil?             # => true
Fast::ClientCert::Cert.parse(":aGVsbG8=:, :d29ybGQ=:").nil?  # => true
Fast::ClientCert::Cert.parse("5").nil?              # => true
```

For the chain, the whole field is ignored — the shared empty value:

```ruby
require "fast/client_cert"

Fast::ClientCert::Chain.parse(":aGVsbG8=:, 5").empty?  # => true
Fast::ClientCert::Chain.parse("!!").empty?             # => true
Fast::ClientCert::Chain.parse("").empty?               # => true
```

`parse!` is the strict view: it raises `Fast::ClientCert::ParseError` with `#offset`, the byte position in the combined field value:

```ruby
require "fast/client_cert"

begin
  Fast::ClientCert::Chain.parse!(":aGVsbG8=:, 5")
rescue Fast::ClientCert::ParseError => e
  e.message  # => "a Client-Cert-Chain member is a Byte Sequence (got Integer)"
  e.offset   # => 12
end
```

`Fast::ClientCert::Chain.valid?(":aGVsbG8=:, 5")  # => false` when you only need a yes/no.

See [Fail-closed: the unauthenticated connection](../explanation/fail-closed-semantics.md) for why the gem refuses to guess.

## Where next

- [Insert Client-Cert and Client-Cert-Chain into forwarded requests](../how-to-guides/insert-the-fields-into-forwarded-requests.md)
- [Validate a Client-Cert at the origin](../how-to-guides/validate-a-client-cert-at-the-origin.md)
- [Convert between PEM blocks and field values](../how-to-guides/convert-between-pem-and-field-values.md)
- [API reference](../reference/api.md)
