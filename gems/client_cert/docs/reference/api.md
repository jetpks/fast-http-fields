# API reference

The definitive page for the whole surface: every signature, return type, class, and rule.

## The module

`Fast::ClientCert`, required as `require "fast/client_cert"`; `Fast::ClientCert::VERSION` is `"0.1.0"`.

Ruby >= 3.4, RubyGems >= 3.5.3, exactly one runtime dependency: fast-sfv.

The two field classes and the four PEM helpers are the public surface; `Checks`, `BINARY`, `EMPTY_PARAMS`, `Item`, `Scan` and `EMPTY` are `private_constant`s.

RFC 9440 is Informational — implementers should weigh it accordingly.

## The two field classes

| class | field | RFC 9440 | wire shape | fail-closed answer |
|---|---|---|---|---|
| `Fast::ClientCert::Cert` | Client-Cert | §2.2 | one Item, a Byte Sequence (the singleton rule rides the Item grammar) | `nil` — no certificate, the unauthenticated connection |
| `Fast::ClientCert::Chain` | Client-Cert-Chain | §2.3 | a List of Byte Sequences in TLS order, splittable across instances | the shared frozen empty value — the same answer an absent field gives |

## Parsing

`Fast::ClientCert::Cert.parse(input)` → the frozen value object or **nil** (the §2.2 recipient view; never raises on field content — malformed syntax, a list-shaped value, the empty field, or an Item whose value is not a Byte Sequence all answer nil; parameters on the Item never fail the field and ride the canonical re-emit); `TypeError` for a non-String/non-Array input.

`Fast::ClientCert::Cert.parse!(input)` → the frozen value object, strict: the wrapped RFC 9651 Item failure with its message and byte offset preserved, then the §2.1 constraint — the Item's value must be a Byte Sequence — raised as ParseError at the value's first non-OWS byte in the combined field value (" 5" fails at 1, not 0), the message naming the type §2.1 states.

`Fast::ClientCert::Cert.valid?(input)` → true exactly when the field carries a certificate — false for malformed content, non-Byte-Sequence items, list-shaped values, the empty field and a wrong input type alike.

`Fast::ClientCert::Chain.parse(input)` → the frozen value object; malformed syntax, the empty List, or ANY member that is not a Byte Sequence is the ENTIRE field ignored — the shared frozen empty value; no member-level filtering.

`Fast::ClientCert::Chain.parse!(input)` → strict: the wrapped List failure with its offset preserved; then the §2.3 member constraint — every member an Item whose value is a Byte Sequence — the FIRST offender in List order raised at that member's first non-OWS byte in the combined field value, quote-aware (a comma inside a quoted parameter does not split); the positioning Scan runs only on this error path.

`Fast::ClientCert::Chain.valid?(input)` → true/false; "" is true (the valid empty List).

Input for all: a String (one field value) or an Array of String field lines, combined with ", " (RFC 9651 §4.2 — "parsers MUST combine all field lines in the same section (header or trailer) that case-insensitively match the field name into one comma-separated field-value").

Examples:

```ruby
require "fast/client_cert"

Fast::ClientCert::Cert.parse(":aGVsbG8=:").der  # => "hello"
Fast::ClientCert::Cert.parse("!!").nil?  # => true
Fast::ClientCert::Cert.valid?(":aGVsbG8=:")  # => true
Fast::ClientCert::Cert.valid?("!!")  # => false
Fast::ClientCert::Chain.parse(":aGVsbG8=:, :d29ybGQ=:").ders  # => ["hello", "world"]
Fast::ClientCert::Chain.parse("").empty?  # => true
Fast::ClientCert::Chain.valid?("")  # => true
```

## The Cert value object

`der` — the DER bytes of the end-entity certificate: a frozen ASCII-8BIT String, bytewise-comparable from day one.

`to_s` — a fresh mutable String, the canonical RFC 9651 §4.1.3 serialization of the held Item, ":<base64>:"; never raises (a parsed value re-emits the parameters it carried).

`==` / `eql?` — canonical-wire-form equality WITHIN the class: a Cert equals a Cert — never a bare Item; `hash` consistent.

`inspect` — `#<Fast::ClientCert::Cert :aGVsbG8=:>`.

Frozen at construction; the DER String is frozen IN PLACE — pass a copy if the buffer is reused.

```ruby
require "fast/client_cert"

cert = Fast::ClientCert::Cert.parse(":aGVsbG8=:")
cert.der  # => "hello"
cert.to_s  # => ":aGVsbG8=:"
cert.inspect  # => "#<Fast::ClientCert::Cert :aGVsbG8=:>"
cert.frozen?  # => true
cert.der.frozen?  # => true
```

## The Chain value object

`ders` — the DER bytes of the chain's certificates in TLS order: a frozen Array of frozen ASCII-8BIT Strings.

`size`, `empty?`, `each` (Enumerator-graceful without a block), `[](index)` — Array semantics (negative indices, nil beyond the ends).

`to_s` — a fresh mutable String, the canonical RFC 9651 §4.1.1 List serialization — the Byte Sequences joined with ", " — "" when none are held (a sender omits the field entirely).

`split(per_line)` — the sender-side cut (§2.3's MAY-split): a frozen Array of canonical field values, each carrying `per_line` certificates — one per instance at 1, the whole chain in one value at the size; the lines recombine through the Array entry point; non-positive per_line raises ArgumentError (a caller bug, never a field error).

`==` / `eql?` / `hash` — class-checked canonical-wire-form equality (a Chain never equals a Cert or a bare Array); `inspect` — `#<Fast::ClientCert::Chain <wire>>`, or `#<Fast::ClientCert::Chain>` when empty.

Frozen at construction; the members Array, the ders view and every DER String are frozen, each DER frozen IN PLACE.

```ruby
require "fast/client_cert"

chain = Fast::ClientCert::Chain.parse(":aGVsbG8=:, :d29ybGQ=:")
chain.ders  # => ["hello", "world"]
chain.size  # => 2
chain.empty?  # => false
chain[0]  # => "hello"
chain[10].nil?  # => true
chain.to_s  # => ":aGVsbG8=:, :d29ybGQ=:"
chain.split(1)  # => [":aGVsbG8=:", ":d29ybGQ=:"]
chain.inspect  # => "#<Fast::ClientCert::Chain :aGVsbG8=:, :d29ybGQ=:>"
Fast::ClientCert::Chain.parse("").inspect  # => "#<Fast::ClientCert::Chain>"
chain.frozen?  # => true
```

## Construction

`Fast::ClientCert::Cert.new(der)` — der is the DER-encoded certificate as a String tagged ASCII-8BIT and not a Token (the encoding IS the Byte Sequence tag — a UTF-8 String would emit as a quoted sf-string, a Token as a token; the bytes are never inspected); anything else raises SerializeError at offset 0 before anything is emitted.

`Fast::ClientCert::Chain.new(ders)` — an Array of such Strings, each member checked through the same shared seam; the empty Array builds the empty value; a non-Array raises SerializeError ("Client-Cert-Chain members are an Array (got …)").

```ruby
require "fast/client_cert"

cert = Fast::ClientCert::Cert.new("hello".b)
cert.der  # => "hello"
cert.to_s  # => ":aGVsbG8=:"
chain = Fast::ClientCert::Chain.new(["hello".b, "world".b])
chain.ders  # => ["hello", "world"]
Fast::ClientCert::Chain.new([]).empty?  # => true
```

## The PEM helpers

| method | signature | returns | raises |
|---|---|---|---|
| `pem_to_field` | `(pem)` | the Item's field value ":<base64>:" — the §2.1 surgery | `Fast::ClientCert::Error` (armor-shape failures: no BEGIN, no END, no payload, a second block); TypeError (non-String) |
| `field_to_pem` | `(field)` | one textual block, the base64 wrapped at 64 characters per line, every line newline-terminated | `Fast::ClientCert::Error` (not a whole base64 item); TypeError (non-String) |
| `pems_to_field` | `(blocks)` | the Client-Cert-Chain field value, members joined ", " | `Fast::ClientCert::Error` (the empty Array); TypeError (non-Array) |
| `field_to_pems` | `(field)` | the Array of blocks in order; `[]` for the empty value | `Fast::ClientCert::Error` (a member that is not a whole base64 item); TypeError (non-String) |

Under the table: the PEM side trusts the armor and never validates base64; the field-value side is strict; usage failures answer the base `Error` — neither a parse defect (the field never parsed) nor a serialization defect (nothing was built).

```ruby
require "fast/client_cert"

block = <<~PEM
  -----BEGIN CERTIFICATE-----
  aGVsbG8=
  -----END CERTIFICATE-----
PEM

Fast::ClientCert.pem_to_field(block)  # => ":aGVsbG8=:"
Fast::ClientCert.field_to_pem(":aGVsbG8=:") == block  # => true
Fast::ClientCert.pems_to_field([block, block])  # => ":aGVsbG8=:, :aGVsbG8=:"
Fast::ClientCert.field_to_pems(":aGVsbG8=:, :aGVsbG8=:").size  # => 2
Fast::ClientCert.field_to_pems("").size  # => 0
```

## Errors

`Fast::ClientCert::Error < StandardError` — the family root, raised in its own right by the PEM helpers (a usage failure).

`Fast::ClientCert::ParseError < Error` — `ParseError.new(message, offset)`, `#offset`: the wrapped substrate failure's byte position, or the offending value's first non-OWS byte in the combined field value (for a chain, the first offender's, quote-aware).

`Fast::ClientCert::SerializeError < Error` — `SerializeError.new(message, offset)`, `#offset` (0: the checks run before anything is emitted); the whole emit path raises this class and never TypeError.

One `rescue Fast::ClientCert::Error` guards every field-content and usage failure; a wrong input type is a caller bug and raises plain TypeError.

```ruby
require "fast/client_cert"

begin
  Fast::ClientCert::Cert.parse!("5")
rescue Fast::ClientCert::ParseError => e
  e.message  # => "Client-Cert: the value is a Byte Sequence (got Integer)"
  e.offset  # => 0
end

begin
  Fast::ClientCert::Cert.new("hello")
rescue Fast::ClientCert::SerializeError => e
  e.message  # => "Client-Cert: the value is a Byte Sequence (got \"hello\")"
  e.offset  # => 0
end

begin
  Fast::ClientCert.pem_to_field("not a block")
rescue Fast::ClientCert::Error => e
  e.message  # => "the PEM block must begin with -----BEGIN CERTIFICATE-----"
end
```

## How the surface is verified

The vectors: RFC 9440's own Appendix A as quoted test vectors — the three Figure 1 PEM blocks, the Figure 2 Client-Cert value, the Figure 3 Client-Cert-Chain value with its per-member forms, mechanically extracted from the corpus ("Generated mechanically from the corpus, never hand-typed") with the DER byte sizes (428/490/522) and the three sha256 digests recorded for bytewise identity — frozen in `test/fast/client_cert/vectors.rb`.

The pins: 17 frozen `parse!` offset pins across the two fields; the PEM behaviors (tolerances, armor failures, the mangled-payload leniency, the 64-character wrap, the exact appendix round-trips) in `test/fast/client_cert/pem.rb`; the 19 allocation paths in `test/fast/client_cert/allocations.rb`; the harness proof in `test/fast/client_cert/smoke.rb`.

The suite totals at writing: **3364 passed / 3364 total (5926 assertions)** at the monorepo root, every gem's suites green together (`bundle exec sus`).

## Requirements

Ruby >= 3.4, RubyGems >= 3.5.3, one runtime dependency (fast-sfv), no OpenSSL, no DER decoding.
