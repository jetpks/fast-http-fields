# Insert Client-Cert and Client-Cert-Chain into forwarded requests

The TTRP's operation per RFC 9440 §2.4 — the processing rules the RFC states for exactly this role.

## What the TTRP sends

RFC 9440 §2.4's three numbered modifications:

> 1. The client certificate is placed in the Client-Cert header field of the dispatched request, as described in Section 2.2.
> 2. If so configured, the validation chain of the client certificate is placed in the Client-Cert-Chain header field of the request, as described in Section 2.3.
> 3. Any occurrence of the Client-Cert or Client-Cert-Chain header fields in the original incoming request MUST be removed or overwritten before forwarding the request. An incoming request that has a Client-Cert or Client-Cert-Chain header field MAY be rejected with an HTTP 400 response.

The TTRP "negotiates the use of a mutually authenticated TLS connection with the client ... and validates the client certificate per its policy and trusted certificate authorities" — the fields carry what the TLS connection already authenticated; the gem builds the field values, never the trust.

## Build the fields

From the connection's certificate: the TLS stack hands the proxy DER bytes or PEM blocks — either entry point builds the field value. PEM blocks through the helpers ([Convert between PEM blocks and field values](convert-between-pem-and-field-values.md)); DER bytes through construction.

```ruby
require "fast/client_cert"

der = "hello".b
ders = ["hello".b, "world".b]

headers = { "client-cert" => Fast::ClientCert::Cert.new(der).to_s,
            "client-cert-chain" => Fast::ClientCert::Chain.new(ders).to_s }
headers["client-cert"]        # => ":aGVsbG8=:"
headers["client-cert-chain"]  # => ":aGVsbG8=:, :d29ybGQ=:"
```

Construction is strict — a sender never puts garbage on the wire: each DER must be a String tagged ASCII-8BIT and not a Token. The DER bytes are frozen in place as part of the value object — pass a copy if the buffer is reused.

The response side of the header names: the gem's boundary is the field value; the proxy's header plumbing is the caller's. No framework API is claimed — a plain Hash stands in for the headers exactly the shape any stack hands you.

## Sanitize the incoming request

The MUST from rule 3, and the non-negotiated case: "Requests to the TTRP made over a TLS connection where the use of client certificate authentication was not negotiated MUST be sanitized by removing any and all occurrences of the Client-Cert and Client-Cert-Chain header fields prior to dispatching the request to the backend server".

The client-injection reason, from Appendix B.1: "Otherwise, a client could inject its own values that would appear to the backend to have come from the TTRP".

```ruby
env = { "REQUEST_METHOD" => "GET",
        "HTTP_HOST" => "origin.example.net",
        "HTTP_CLIENT_CERT" => ":aGVsbG8=:" }

forwarded = env.dup.delete_if { |key,| key.start_with?("HTTP_CLIENT_CERT") }
forwarded.key?("HTTP_CLIENT_CERT")  # => false
forwarded  # => {"REQUEST_METHOD" => "GET", "HTTP_HOST" => "origin.example.net"}
```

Rule 3's 400 allowance is a policy choice — strip, overwrite, or reject; all three conform.

See [Field injection and the trusted path](../explanation/field-injection-and-trusted-path.md).

## Split the chain for compression

RFC 9440 §2.3: "For header compression purposes, it might be advantageous to split lists into multiple instances", and §3.1's caution — the field values' size and variation "can reduce compression efficiency significantly".

```ruby
require "fast/client_cert"

chain = Fast::ClientCert::Chain.new(["hello".b, "world".b])

lines = chain.split(1)  # one certificate per field instance
lines                                   # => [":aGVsbG8=:", ":d29ybGQ=:"]
Fast::ClientCert::Chain.parse(lines) == chain  # => true
```

§3.2's size note — "recipients may need to be configured to allow for a larger maximum header size" and the 431 status exists for the refusal.

The `per_line` contract: a caller choice, so a non-positive one is a caller bug — ArgumentError, never a field error.

## The rules around the fields

- Both fields are request-only: the RFC states of each that it "is only for use in HTTP requests and MUST NOT be used in HTTP responses".
- "Forward proxies and other intermediaries MUST NOT add the Client-Cert or Client-Cert-Chain header fields to requests or modify an existing Client-Cert or Client-Cert-Chain header field. Similarly, clients MUST NOT employ the Client-Cert or Client-Cert-Chain header field in requests".
- The chain membership rules — no end-entity certificate in the chain, the root MAY be omitted, Client-Cert-Chain MUST NOT appear unless Client-Cert is present.
- §3.3's resumption caution — implementations unable to provide the values on resumption "SHOULD either disable resumption for connections with client certificates or initially omit a Client-Cert or Client-Cert-Chain field".
- §2.4's caching rule — a response selected by Client-Cert "MUST either be uncacheable ... or be designated for selective reuse only for subsequent requests with the same Client-Cert header field value by sending a 'Vary: Client-Cert' response header", and a TTRP seeing the fields in Vary "SHOULD prevent the user agent from caching the response by transforming the value of the Vary response header field to '*'".

Every one of these is a rule about how the fields are USED — the gem's parse, emit and fail-closed semantics never police them; the caller does.

See [API reference](../reference/api.md).
