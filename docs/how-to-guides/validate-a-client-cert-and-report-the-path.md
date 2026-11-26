# Validate a client certificate and report the path

TLS ends at the proxy, not at you — but the client's certificate travels on in a field. This guide reads it, treats its absence honestly, and answers the client with a Proxy-Status that says what you decided. Two gems, one decision.

## Read the certificate

The read and the comparison against the certificate you expect:

```ruby
require "fast/client_cert"
require "fast/proxy_status"

env = { "HTTP_CLIENT_CERT" => ":aGVsbG8=:" }

cert = Fast::ClientCert::Cert.parse(env["HTTP_CLIENT_CERT"] || "")
cert.nil?  # => false

pinned_der = "hello".b  # in real life: the certificate your CA issued, as DER bytes
cert.der == pinned_der  # => true
```

`der` is the certificate's bytes exactly as TLS carried them (the five-byte stand-in stands for a real certificate). DER bytes are the certificate's raw binary form. Comparing them against the certificate you pinned is the whole check, and what "pinned" means is your policy.

For the OpenSSL digest comparison: [validate a client certificate at the origin](../../gems/client_cert/docs/how-to-guides/validate-a-client-cert-at-the-origin.md).

## No certificate means unauthenticated

Absent and unreadable both answer nil — no certificate, the unauthenticated connection:

```ruby
env = {}  # the proxy forwarded no certificate
cert = Fast::ClientCert::Cert.parse(env["HTTP_CLIENT_CERT"] || "")
cert.nil?  # => true
```

Treat the connection as unauthenticated — that is the field's honest answer, never an exception. Whether that is a 401, a 403, or a different body is your access policy. The client certificate is only trustworthy from a proxy you trust — see [field injection and trusted path](../../gems/client_cert/docs/explanation/field-injection-and-trusted-path.md).

## Read the chain

The validation chain the proxy forwards beside the certificate:

```ruby
env = { "HTTP_CLIENT_CERT" => ":aGVsbG8=:", "HTTP_CLIENT_CERT_CHAIN" => ":d29ybGQ=:" }

chain = Fast::ClientCert::Chain.parse(env["HTTP_CLIENT_CERT_CHAIN"] || "")
chain.ders  # => ["world"]
```

The chain is the certificates used to validate the end-entity one, in TLS order, as raw bytes. The gem splits and recombines the wire forms; validating the chain itself is OpenSSL's job on your side (see [convert between PEM and field values](../../gems/client_cert/docs/how-to-guides/convert-between-pem-and-field-values.md)).

## Report the outcome with Proxy-Status

A denied request can say so in the field the client's operators already read:

```ruby
denial = Fast::ProxyStatus.new([
  Fast::ProxyStatus::Hop.new(Fast::SFV::Token.new("origin"),
    { "error" => Fast::SFV::Token.new("http_request_denied") })
])
denial.to_s  # => "origin;error=http_request_denied"

Fast::ProxyStatus.recommended_status("http_request_denied")  # => 403
```

`http_request_denied` is one of the registry's 32 error types and the registry recommends the status (403) the RFC itself pairs with it. On the success path the origin simply writes its own member first and every proxy appends itself on the way back — see the sibling how-to [handle a request with Priority, Digest and Proxy-Status](handle-a-request-with-priority-digest-and-proxy-status.md) and the per-gem guide [append yourself to Proxy-Status](../../gems/proxy_status/docs/how-to-guides/append-yourself-to-proxy-status.md).

## What this guide did not cover

- The TTRP's own side — building and sanitizing the fields when you ARE the proxy — see [insert the fields into forwarded requests](../../gems/client_cert/docs/how-to-guides/insert-the-fields-into-forwarded-requests.md).
- PEM conversions: [convert between PEM and field values](../../gems/client_cert/docs/how-to-guides/convert-between-pem-and-field-values.md).
- The [family map](../reference/family-map.md) for the whole family's shape.
- The [explanations](../explanation/why-lenient-parse-strict-emit.md) for the design choices behind the handler.
