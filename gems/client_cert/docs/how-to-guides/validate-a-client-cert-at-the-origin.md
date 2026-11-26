# Validate a Client-Cert at the origin

The origin's operation: consume the fields the TTRP sent. The OpenSSL examples are the CALLER's side — the gem itself never touches OpenSSL.

## Read the field

Rack exposes a request's Client-Cert header as `env["HTTP_CLIENT_CERT"]` (Rack's CGI-derived convention: HTTP_ + uppercased, dashes to underscores) — a String when present, nil when absent. The gem takes no Rack dependency; the examples use a plain Hash standing in for env, exactly the shape Rack hands you.

```ruby
require "fast/client_cert"

env = { "REQUEST_METHOD" => "GET",
        "HTTP_HOST" => "origin.example.net",
        "HTTP_CLIENT_CERT" => ":aGVsbG8=:" }

cert = Fast::ClientCert::Cert.parse(env["HTTP_CLIENT_CERT"] || "")
cert.der  # => "hello"
```

The absent header: nil is a caller bug for `parse` (TypeError), so pass the empty field — the parse answers nil, the same answer an unreadable field gives:

```ruby
require "fast/client_cert"

env = { "REQUEST_METHOD" => "GET" }
Fast::ClientCert::Cert.parse(env["HTTP_CLIENT_CERT"] || "").nil?  # => true
```

## The fail-closed answer

nil IS the decision input: "Backend origin servers may then use the Client-Cert header field of the request to determine if the connection from the client to the TTRP was mutually authenticated and, if so, the certificate thereby presented by the client. Access control decisions based on the client certificate (or lack thereof) can be conveyed by selecting response content as appropriate or with an HTTP 403 response, if the certificate is deemed unacceptable for the given context".

- Absent and malformed both answer nil — the unauthenticated connection:

```ruby
require "fast/client_cert"

Fast::ClientCert::Cert.parse("not a field")  # => nil
```

- A present certificate is yours to judge — the 403 or the content-selection the RFC names.
- The strict view for diagnostics is `parse!` (its offset pinning the byte, not a policy).

RFC 9440 §1's own use cases — "access control decisions, audit logging, and binding issued tokens or cookies to a certificate" — the reasons an origin reads this field at all.

## Compare against an OpenSSL digest

The idiom: the DER bytes are the identity — digest them with OpenSSL and compare against the digests you pinned when the certificate was issued.

```ruby
require "fast/client_cert"
require "openssl"

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

allowed = { "bfaf1f7e070f9fa8dd62905f158da73f84a1136624fbafcc9393c8f7287a69eb" => "client-BC" }
allowed[OpenSSL::Digest.hexdigest("SHA256", cert.der)]  # => "client-BC"
```

`OpenSSL::Digest.hexdigest("SHA256", cert.der)` answers the same hex the stdlib's `Digest::SHA256.hexdigest` answers — either side of the comparison is the caller's; and the comparison is over the DER the field carries, so it is exactly as trustworthy as the path the field arrived on.

OpenSSL here is the caller's tool — the gem never requires it; `Fast::ClientCert` reads and writes the field grammar and leaves every certificate operation to the origin.

## Read the certificate with OpenSSL

The whole DER is available — RFC 9440 Appendix B.3: "this document opted to pass the full, encoded certificate as the value of the Client-Cert field", so the origin reads whatever it needs from the certificate itself.

```ruby
require "fast/client_cert"
require "openssl"

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

certificate = OpenSSL::X509::Certificate.new(cert.der)
certificate.subject.to_s   # => "/CN=BC"
certificate.issuer.to_s    # => "/O=Let's Authenticate/CN=LA Intermediate CA"
certificate.serial.to_s    # => "7"
```

Audit logging reads the same object — the RFC's §1 use-case list is the menu.

## Read the chain

`Fast::ClientCert::Chain.parse(env["HTTP_CLIENT_CERT_CHAIN"] || "")` — the same fail-closed answer shape: the empty value for an absent or malformed field, and a member violation drops the whole field.

The membership rules are the origin's policies, stated as the RFC states them: the chain does not include the end-entity certificate (compare `chain.ders` against `cert.der` if you must), the root MAY be omitted, and Client-Cert-Chain MUST NOT appear unless Client-Cert is present — check that pairing before trusting the chain.

```ruby
require "fast/client_cert"
require "openssl"

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

chain = Fast::ClientCert::Chain.parse(Fast::ClientCert.pems_to_field([second_block, third_block]))
chain.ders.map { |der| OpenSSL::X509::Certificate.new(der).subject.to_s }
# => ["/O=Let's Authenticate/CN=LA Intermediate CA", "/C=US/O=Let's Authenticate/CN=Let's Authenticate Root Authority"]
```

See [Convert between PEM blocks and field values](convert-between-pem-and-field-values.md) for the blocks, [API reference](../reference/api.md) for the reader surface.

## Trust only the TTRP

The MUST: "In order to prevent field injection, backend servers MUST only accept the Client-Cert and Client-Cert-Chain header fields from a trusted TTRP (or other proxy in a trusted path from the TTRP)". The field value carries no proof of its origin — the connection it arrived on does.

The origin's checklist is RFC 9440 §4's — accept the fields only on the trusted path, and let the fail-closed parse make everything else the unauthenticated answer.

See [Field injection and the trusted path](../explanation/field-injection-and-trusted-path.md).
