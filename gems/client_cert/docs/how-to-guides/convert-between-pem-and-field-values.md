# Convert between PEM blocks and field values

The PEM round-trips: the RFC 9440 §2.1 string surgery both directions, at both levels (one certificate and a whole chain).

## The §2.1 surgery

The RFC's own note: "Note that certificates are often stored in an encoded textual format, such as the one described in Section 5.1 of [RFC7468], which is already nearly compatible with a Byte Sequence. If certificates are encoded as such, it will be sufficient to replace '---(BEGIN|END) CERTIFICATE---' with ':' and remove line breaks in order to generate an appropriate item".

```ruby
require "fast/client_cert"

block = <<~PEM
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

value = Fast::ClientCert.pem_to_field(block)
cert = Fast::ClientCert::Cert.parse(value)
cert.der.bytesize  # => 428
cert.to_s == value  # => true
```

The tolerances:

- Blank lines may lead and follow the block:

```ruby
require "fast/client_cert"

block = <<~PEM
  -----BEGIN CERTIFICATE-----
  aGVsbG8=
  -----END CERTIFICATE-----
PEM

Fast::ClientCert.pem_to_field("\n\n#{block}\n") == Fast::ClientCert.pem_to_field(block)  # => true
```

- CRLF line endings are tolerated.
- The armor-shape failures raise `Fast::ClientCert::Error` — no BEGIN line ("the PEM block must begin with -----BEGIN CERTIFICATE-----"), the END missing, no payload, or content after the END ("one PEM block at a time — pass an Array of blocks for a chain").

## The inverse

`field_to_pem` — the base64 wrapped at 64 characters per line, every line (the END line included) newline-terminated, the textual encoding's own form.

The exact round-trip on the Appendix A values: `field_to_pem(value) == block` — the Figure 2 value reproduces the Figure 1 first block byte-for-byte, both chain members likewise.

The wrap rule:

```ruby
require "fast/client_cert"

pem = Fast::ClientCert.field_to_pem(":#{'A' * 68}:")
pem.lines.map { |line| line.chomp.length }  # => [27, 64, 4, 25]
```

The strict side: a value that is not a whole base64 item raises `Fast::ClientCert::Error` before anything is written — colons on both ends, a non-empty interior of base64 alphabet characters with padding only at the end, a length that is a multiple of four. Message forms: `field_to_pem("aGVsbG8=")` → `"the value is not a :base64: item (got \"aGVsbG8=\")"`; `field_to_pem(":aGVsbG8=:;q=1")` → the same class naming the whole value.

## The chain pair

`pems_to_field(blocks)` — each block through the per-block surgery, the members joined with the canonical ", " separator; the empty Array raises Error ("nothing to convert — the blocks Array is empty"); TypeError for a non-Array.

`field_to_pems(value)` — the members split on the separator commas (base64 cannot carry one — the alphabet has no comma), each stripped of the OWS around it and converted exactly as `field_to_pem` demands; the empty value answers no blocks; TypeError for a non-String.

```ruby
require "fast/client_cert"

second_block = <<~PEM
  -----BEGIN CERTIFICATE-----
  MIIB5jCCAYugAwIBAgIBFjAKBggqhkjOPQQDAjBWMQswCQYDVQQGEwJVUzEbMBkG
  A1UECgwSTGV0J3MgQXV0aGVudGljYXRlMSowKAYDVQQDDCFMZXQncyBBdXRoZW50
  aWNhdGUgUm9vdCBBdXRob3JpdHkwHhcNMjAwMTE0MjEzMjMwWhcNMzAwMTExMjEz
  MjMwWjA6MRswGQYDVQQKDBJMZXQncyBBdXRoZW50aWNhdGUxGzAZBgNVBAMMEkxB
  IEludGVybWVkaWF0ZSBDQTBZMBMGByqGSM49AgEGCCqGSM49AwEHA0IABJf+aA54
  RC5pyLAR5yfXVYmNpgd+CGUTDp2KOGhc0gK91zxhHesEYkdXkpS2UN8Kati+yHtW
  CV3kkhCngGyv7RqjZjBkMB0GA1UdDgQWBBRm3WjLa38lbEYCuiCPct0ZaSED2DAf
  BgNVHSMEGDAWgBTEA2Q6eecKu9g9yb5glbkhhVINGDASBgNVHRMBAf8ECDAGAQH/
  AgEAMA4GA1UdDwEB/wQEAwIBhjAKBggqhkjOPQQDAgNJADBGAiEA5pLvaFwRRkxo
  mIAtDIwg9D7gC1xzxBl4r28EzmSO1pcCIQCJUShpSXO9HDIQMUgH69fNDEMHXD3R
  RX5gP7kuu2KGMg==
  -----END CERTIFICATE-----
PEM

third_block = <<~PEM
  -----BEGIN CERTIFICATE-----
  MIICBjCCAaygAwIBAgIJAKS0yiqKtlhoMAoGCCqGSM49BAMCMFYxCzAJBgNVBAYT
  AlVTMRswGQYDVQQKDBJMZXQncyBBdXRoZW50aWNhdGUxKjAoBgNVBAMMIUxldCdz
  IEF1dGhlbnRpY2F0ZSBSb290IEF1dGhvcml0eTAeFw0yMDAxMTQyMTI1NDVaFw00
  MDAxMDkyMTI1NDVaMFYxCzAJBgNVBAYTAlVTMRswGQYDVQQKDBJMZXQncyBBdXRo
  ZW50aWNhdGUxKjAoBgNVBAMMIUxldCdzIEF1dGhlbnRpY2F0ZSBSb290IEF1dGhv
  cml0eTBZMBMGByqGSM49AgEGCCqGSM49AwEHA0IABFoaHU+Z5bPKmGzlYXtCf+E6
  HYj62fORaHDOrt+yyh3H/rTcs7ynFfGn+gyFsrSP3Ez88rajv+U2NfD0o0uZ4Pmj
  YzBhMB0GA1UdDgQWBBTEA2Q6eecKu9g9yb5glbkhhVINGDAfBgNVHSMEGDAWgBTE
  A2Q6eecKu9g9yb5glbkhhVINGDAPBgNVHRMBAf8EBTADAQH/MA4GA1UdDwEB/wQE
  AwIBhjAKBggqhkjOPQQDAgNIADBFAiEAmAeg1ycKHriqHnaD4M/UDBpQRpkmdcRF
  YGMg1Qyrkx4CIB4ivz3wQcQkGhcsUZ1SOImd/lq1Q0FLf09rGfLQPWDc
  -----END CERTIFICATE-----
PEM

chain_value = Fast::ClientCert.pems_to_field([second_block, third_block])
chain = Fast::ClientCert::Chain.parse(chain_value)
chain.size                # => 2
chain.ders.map(&:bytesize)  # => [490, 522]

Fast::ClientCert.field_to_pems(chain_value) == [second_block, third_block]  # => true
```

The composition with the field classes:

```ruby
require "fast/client_cert"

block = <<~PEM
  -----BEGIN CERTIFICATE-----
  aGVsbG8=
  -----END CERTIFICATE-----
PEM

Fast::ClientCert::Chain.parse(Fast::ClientCert.pems_to_field([block, block])).to_s == Fast::ClientCert.pems_to_field([block, block])  # => true
Fast::ClientCert::Cert.parse(Fast::ClientCert.pem_to_field(block)).to_s == Fast::ClientCert.pem_to_field(block)  # => true
```

## What each side trusts

- The PEM side trusts the armor and never validates the base64 — a mangled payload becomes a field value that fails the Structured Fields parse downstream, fail-closed like any malformed field:

```ruby
require "fast/client_cert"

block = <<~PEM
  -----BEGIN CERTIFICATE-----
  not base64!!
  -----END CERTIFICATE-----
PEM

value = Fast::ClientCert.pem_to_field(block)  # => ":not base64!!:"
Fast::ClientCert::Cert.parse(value).nil?  # => true
```

- The field-value side is strict: a sender never writes garbage.
- Wrong input types raise TypeError on both sides — a caller bug, never field content.

See [Fail-closed: the unauthenticated connection](../explanation/fail-closed-semantics.md) and [API reference](../reference/api.md).
