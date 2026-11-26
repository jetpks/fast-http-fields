# Start here: one request, one response, five fields

You run a Ruby service that speaks HTTP. Modern HTTP defines fields for what the story needs: how urgently the client wants the answer, whether the body arrived intact, who the client proved itself to be, and what happened on the way. This tutorial walks one request and one response through all five gems. Ten minutes, one file, everything runnable.

## What you need

Ruby 3.4 or newer. The four field gems installed (`gem install fast-priority fast-digest fast-client-cert fast-proxy-status`) — fast-sfv comes along as the shared substrate (the grammar the fields are written in; see [the SFV substrate](../explanation/the-sfv-substrate.md)).

The fence convention in one sentence: examples use a plain Hash standing in for the request environment, the shape Rack-style frameworks hand you (`"HTTP_PRIORITY"` and friends) — no framework dependency, the family's own how-to convention.

## The request arrives

The Priority field is a hint from the client about how urgently it wants the answer (RFC 9218):

```ruby
require "fast/priority"
require "fast/digest"
require "fast/client_cert"

env = {
  "HTTP_PRIORITY"       => "u=1, i",
  "HTTP_CONTENT_DIGEST" => "sha-256=:LPJNul+wow4m6DsqxbninhsWHlwfp0JecwQzYpOLmCQ=:",
  "HTTP_CLIENT_CERT"    => ":aGVsbG8=:"
}
request_body = "hello"

priority = Fast::Priority.parse(env["HTTP_PRIORITY"] || "")
priority.urgency      # => 1
priority.incremental  # => true
```

Urgency 1 means answer sooner rather than later (0 is the most urgent, 7 the least). Incremental true means the client is happy to receive the answer in pieces. No Priority field, or one you cannot read, answers the defaults — urgency 3, not incremental — never an exception. The `|| ""` is the absent-header idiom (nil is a caller bug; the empty field is the field's own answer).

For more: the [priority field tutorial](../../gems/priority/docs/tutorials/priority-field.md) and [why lenient-parse, strict-emit](../explanation/why-lenient-parse-strict-emit.md).

## Is the body intact?

Content-Digest is a checksum the sender attached to the bytes it sent, hashed with a named algorithm (RFC 9530):

```ruby
sent = Fast::Digest::ContentDigest.parse(env["HTTP_CONTENT_DIGEST"] || "")
sent.empty?  # => false
sent["sha-256"] == Digest::SHA256.digest(request_body)  # => true
```

Hash what you actually received and compare bytewise — that is the whole check. An unreadable digest field answers the empty value (`sent.empty?` true), the same as no field at all: fail-closed, never an exception. Ruby's own `Digest` does the hashing — the gem adds no crypto of its own.

For more: the [digest fields tutorial](../../gems/digest/docs/tutorials/digest-fields.md).

## Who is asking?

Client-Cert is the field a proxy forwards when TLS ends in front of you — it carries the client's certificate to your origin (RFC 9440):

```ruby
cert = Fast::ClientCert::Cert.parse(env["HTTP_CLIENT_CERT"] || "")
cert.nil?  # => false
cert.der   # => "hello"
```

`der` is the certificate's raw bytes, exactly as TLS carried them (the stand-in here is five bytes; a real one is hundreds). Nil means no certificate — the connection was not mutually authenticated, and that is the field's honest answer, not an error. What you compare those bytes against — a pinned certificate, a digest of one — is your policy.

For more: the [client-cert fields tutorial](../../gems/client_cert/docs/tutorials/client-cert-fields.md).

## When a field is unreadable

No gem in this family raises on field content. Each field's RFC defines what a recipient does with input it cannot read, and the gem answers exactly that:

```ruby
Fast::ClientCert::Cert.parse("not a field")               # => nil
Fast::Digest::ContentDigest.parse("not a field").empty?   # => true
Fast::Priority.parse("not a field").urgency               # => 3
```

No certificate, no digest, the priority defaults. When you need the truth instead — a sender debugging its own output — the strict `parse!` raises with the byte where the field went wrong. See [why lenient-parse, strict-emit](../explanation/why-lenient-parse-strict-emit.md).

## The answer goes back

The response carries its own story: a digest of what you sent (RFC 9530), and a Proxy-Status field reporting the path (RFC 9209):

```ruby
require "fast/proxy_status"

response_digest = Fast::Digest::ReprDigest.of("sha-256", request_body)
response_digest.to_s  # => "sha-256=:LPJNul+wow4m6DsqxbninhsWHlwfp0JecwQzYpOLmCQ=:"

status = Fast::ProxyStatus.new([Fast::ProxyStatus::Hop.new(Fast::SFV::Token.new("origin"))])
status.to_s  # => "origin"

answered = Fast::ProxyStatus.append(status, Fast::SFV::Token.new("tls-proxy"))
answered.to_s  # => "origin, tls-proxy"
```

The origin writes the first member. Each intermediary on the way back appends itself, so the client can read the whole path in one field. A failing hop carries an error type — one of the registry's 32 names, each with the HTTP status it recommends — that story belongs to the proxy-status gem.

For more: the [diagnostics fields tutorial](../../gems/proxy_status/docs/tutorials/diagnostics-fields.md).

## What you just met

| Field(s) | Gem | RFC | What it did in this story |
|----------|-----|-----|---------------------------|
| Priority | [fast-priority](../../gems/priority/README.md) | RFC 9218 | how urgently the client wanted the answer |
| Content-Digest | [fast-digest](../../gems/digest/README.md) | RFC 9530 | the checksum on the request body |
| Client-Cert | [fast-client-cert](../../gems/client_cert/README.md) | RFC 9440 | who the client proved itself to be |
| Repr-Digest | [fast-digest](../../gems/digest/README.md) | RFC 9530 | the checksum on the response body |
| Proxy-Status | [fast-proxy-status](../../gems/proxy_status/README.md) | RFC 9209 | the path the response travelled |

Each gem's README links its full tree — tutorial, how-to guides, reference, explanations — where the register turns technical and RFC section by section. The [family map](../reference/family-map.md) is the map of the whole layer. The two root how-tos — [handle a request with Priority, Digest and Proxy-Status](../how-to-guides/handle-a-request-with-priority-digest-and-proxy-status.md) and [validate a client certificate and report the path](../how-to-guides/validate-a-client-cert-and-report-the-path.md) — are the next step when you want the composed handler for real.
