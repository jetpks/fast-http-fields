# fast-client-cert

fast-client-cert is the RFC 9440 implementation for Ruby: the Client-Cert and Client-Cert-Chain request fields a TLS-terminating reverse proxy sends to convey the client certificate of a mutually authenticated TLS connection, built on fast-sfv.

## What it is

`Fast::ClientCert::Cert` implements RFC 9440 §2.2: "This field contains the end-entity certificate used by the client in the TLS handshake" — one Structured Fields Item carrying the certificate's DER bytes as a Byte Sequence (§2.1: "the binary DER certificate is encoded using base64 ... and delimited with colons on either side"). It is a singleton field ("It is a singleton header field value as defined in Section 5.5 of [HTTP], which MUST NOT have a list of values or occur multiple times in a request") — the Item grammar enforces that by itself, so a list-shaped value is a malformed field.

`Fast::ClientCert::Chain` implements §2.3: "the certificate chain used for validation of the end-entity certificate" as a List of Byte Sequences, "The order is the same as the ordering in TLS". The field "MAY have a list of values or occur multiple times in a request" — an Array of field lines is its native split form, and `split` cuts a held chain back into per-instance lines. The membership rules (the chain "does not itself include the end-entity certificate", "The root certificate MAY be omitted", "Client-Cert-Chain MUST NOT appear unless Client-Cert is also present") are request-level policies over opaque DER bytes — documented in the RFC, never enforced here.

The four PEM helpers are the §2.1 string surgery both directions, pure Ruby — no OpenSSL, the DER bytes opaque: "it will be sufficient to replace ---(BEGIN|END) CERTIFICATE--- with ':' and remove line breaks in order to generate an appropriate item."

The lenient parse (`parse`) answers a recipient's view and never raises on field content; the strict parse (`parse!`) tells the truth with byte offsets; `valid?` mirrors it with a boolean; `to_s` and construction are always strict; results are frozen value objects; one runtime dependency (fast-sfv), no OpenSSL, no DER decoding.

RFC 9440 is an Informational RFC — implementers should weigh it accordingly. Both fields "are only for use in HTTP requests and MUST NOT be used in HTTP responses", and RFC 9440 §4 warns that backend servers "MUST only accept the Client-Cert and Client-Cert-Chain header fields from a trusted TTRP" — sanitization and trust are the deployment's duties, never this gem's.

## Installation

```sh
gem install fast-client-cert
```

In a Gemfile:

```ruby
gem "fast-client-cert"
```

Require path is `fast/client_cert`:

```ruby
require "fast/client_cert"
```

Requires Ruby >= 3.4 and RubyGems >= 3.5.3; the only runtime requirement is fast-sfv.

## Quickstart

Read a Client-Cert field and compare the DER bytes — the day-one idiom, bytewise against `File.binread("client.der")`:

```ruby
require "fast/client_cert"

cert = Fast::ClientCert::Cert.parse(":aGVsbG8=:")
cert.der   # => "hello" (the DER bytes, a frozen ASCII-8BIT String)
cert.to_s  # => ":aGVsbG8=:" (the canonical wire form)
```

The fail-closed story: a field a recipient cannot read is the field treated as absent — no certificate, the unauthenticated connection. `parse` answers nil for malformed content, a list-shaped value (the singleton rule) and an Item that is not a Byte Sequence alike; `parse!` is the strict truth, positioned:

```ruby
Fast::ClientCert::Cert.parse("not a field")  # => nil (no certificate, the unauthenticated connection)
Fast::ClientCert::Cert.valid?("!!")          # => false
begin
  Fast::ClientCert::Cert.parse!("5")
rescue Fast::ClientCert::ParseError => e
  e.message  # => "Client-Cert: the value is a Byte Sequence (got Integer)"
  e.offset   # => 0
end
```

The chain, its split form and the recombine:

```ruby
chain = Fast::ClientCert::Chain.parse(":aGVsbG8=:, :d29ybGQ=:")
chain.ders   # => ["hello", "world"] (TLS order, frozen)
chain.to_s   # => ":aGVsbG8=:, :d29ybGQ=:"

lines = chain.split(1)  # one certificate per field instance
lines                    # => [":aGVsbG8=:", ":d29ybGQ=:"]
Fast::ClientCert::Chain.parse(lines) == chain  # => true (the lines recombine)

received = [":aGVsbG8=:", " :d29ybGQ=:"]
Fast::ClientCert::Chain.parse(received).to_s  # => ":aGVsbG8=:, :d29ybGQ=:" (the lines combine)
```

A malformed chain, or any member that is not a Byte Sequence, is the whole field ignored — a valid certificate beside a bad one drops with it:

```ruby
Fast::ClientCert::Chain.parse(":aGVsbG8=:, 5").empty?  # => true (the whole field ignored)
empty = Fast::ClientCert::Chain.parse("!!")
empty.empty?  # => true (the shared empty value, the same answer an absent field gives)
Fast::ClientCert::Chain.parse("").empty?  # => true ("" is the valid empty List)
Fast::ClientCert::Chain.valid?("")  # => true
```

## The PEM surgery

Certificates usually live as RFC 7468 text blocks; RFC 9440 §2.1 notes the conversion "will be sufficient" as pure string surgery. Both directions, at both levels:

```ruby
block = <<~PEM
  -----BEGIN CERTIFICATE-----
  aGVsbG8=
  -----END CERTIFICATE-----
PEM

Fast::ClientCert.pem_to_field(block)      # => ":aGVsbG8=:"
Fast::ClientCert.field_to_pem(":aGVsbG8=:") == block  # => true (the base64 wraps at 64 characters per line, every line newline-terminated)
```

The chain pair:

```ruby
first = <<~PEM
  -----BEGIN CERTIFICATE-----
  aGVsbG8=
  -----END CERTIFICATE-----
PEM

second = <<~PEM
  -----BEGIN CERTIFICATE-----
  d29ybGQ=
  -----END CERTIFICATE-----
PEM

Fast::ClientCert.pems_to_field([first, second])  # => ":aGVsbG8=:, :d29ybGQ=:"
Fast::ClientCert.field_to_pems(":aGVsbG8=:, :d29ybGQ=:") == [first, second]  # => true
```

The PEM side trusts the armor and never validates base64 — a mangled payload becomes a field value that fails the Structured Fields parse downstream, fail-closed like any malformed field. The field-value side is strict: a sender never writes garbage, so a value without colons on both ends and a whole base64 interior raises `Fast::ClientCert::Error` before anything is written; wrong input types raise TypeError; the empty blocks Array is a usage failure ("nothing to convert"); the empty chain value answers no blocks.

## The guarantees

`parse` never raises on field content. `parse!` raises `Fast::ClientCert::ParseError` positioned at the offending byte — the wrapped substrate failure with its offset preserved, or the Byte Sequence constraint at the value's first non-OWS byte (for a chain, the first offending member's, quote-aware: a comma inside a quoted parameter does not split). `to_s` and construction are always strict: a DER that is not a String tagged ASCII-8BIT (the encoding IS the Byte Sequence tag — a UTF-8 String would emit as a quoted sf-string) or a Token raises `Fast::ClientCert::SerializeError` before anything is emitted. `Fast::ClientCert::Error` → `ParseError`/`SerializeError`, both carrying `#offset` — one rescue guards the whole gem; a wrong input type is a caller bug and raises plain TypeError. The value objects are frozen — the Cert, its DER, the Chain, its ders Array and every DER String; the DER bytes are frozen in place on construction, so pass a copy if the buffer is reused.

Parameters ride the canonical re-emit and never fail either field — §2.2/§2.3 say Byte Sequence, not "a parameterless item", and nothing in RFC 9440 defines one.

## Status

Current release 0.1.0; changelog at [CHANGELOG.md](CHANGELOG.md). The documentation tree and this gem's 0.1.0 release land together (docs are part of the product — the family's release rule).

MIT license; source at `https://github.com/jetpks/fast-http-fields`.
