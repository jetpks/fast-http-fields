# The whole certificate as opaque DER

RFC 9440 Appendix B.3 — why the full certificate travels, why the DER bytes stay opaque, and why the gem is pure Ruby with no OpenSSL.

## Why the whole certificate

Appendix B.3's opening: "Different applications will have varying requirements about what information from the client certificate is needed, such as the subject and/or issuer distinguished name, subject alternative name(s), serial number, subject public key info, fingerprint, etc. Furthermore, some applications, such as that described in [RFC8705], make use of the entire certificate. In order to accommodate the latter and ensure wide applicability by not trying to cherry-pick particular certificate information, this document opted to pass the full, encoded certificate as the value of the Client-Cert field".

Cherry-picking would have made the field an API surface that grows with every new use case; the whole certificate makes the field a fixed shape whose meaning is the caller's to read. RFC 9440 §1's use-case list — "access control decisions, audit logging, and binding issued tokens or cookies to a certificate" — all read from the same bytes.

## Why the bytes stay opaque

RFC 9440 §2.1's encoding: "The headers in this document encode certificates as Byte Sequences (Section 3.3.5 of [STRUCTURED-FIELDS]) where the value of the binary data is a DER-encoded [ITU.X690] X.509 certificate [RFC5280]".

The gem's side of that contract: it parses the Structured Fields grammar (RFC 9651 §3.3.5's colons-and-base64 Byte Sequence) and hands over the decoded DER bytes; certificate semantics — the subject, the validity, the extensions, the chain relationships — are never read. DER structure is the caller's, nothing in this gem depends on it.

The boundary: the RFC's membership rules (the chain excludes the end-entity, the root MAY be omitted, the chain MUST NOT appear without Client-Cert) are policies over opaque bytes — the gem documents them and enforces none, because enforcing them would mean reading the bytes.

## Why pure Ruby, no OpenSSL

RFC 9440 §2.1's own note: "Note that certificates are often stored in an encoded textual format, such as the one described in Section 5.1 of [RFC7468], which is already nearly compatible with a Byte Sequence. If certificates are encoded as such, it will be sufficient to replace '---(BEGIN|END) CERTIFICATE---' with ':' and remove line breaks in order to generate an appropriate item" — the conversion the RFC calls "sufficient" is text manipulation, and the gem does exactly that.

Appendix B.3's division of labor: "The validation of the client certificate and chain of the mutually authenticated TLS connection is typically performed by the TTRP during the handshake. With the responsibility of certificate validation falling on the TTRP, the end-entity certificate is oftentimes sufficient for the needs of the origin server" — validation is not this gem's job either; the bytes are conveyance, not judgment.

When the origin DOES need to read or verify the certificate, OpenSSL is right there (`OpenSSL::X509::Certificate.new(cert.der)`) — the docs show that in the origin how-to; the gem itself takes no OpenSSL dependency and stays pure Ruby over fast-sfv.

## What the gem refuses to do

- No DER decoding (the bytes are opaque; a mangled payload fails the Structured Fields parse, not a certificate parse).
- No certificate validation (the TTRP's job per Appendix B.3).
- No chain building or trust-store consultation (the caller's job).
- No policy enforcement (the membership rules are documented, never policed).

Each refusal is the same principle: the field grammar is the contract, the certificate is the payload.

See [Validate a Client-Cert at the origin](../how-to-guides/validate-a-client-cert-at-the-origin.md) for the caller-side OpenSSL idioms and [API reference](../reference/api.md) for the surface.
