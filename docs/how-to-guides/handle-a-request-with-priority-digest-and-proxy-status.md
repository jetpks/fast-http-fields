# Handle a request with Priority, Digest and Proxy-Status together

You sit between a client and an upstream service. The request tells you how urgently the client wants the answer and — for an upload — what bytes it claims to have sent. The upstream's response tells you how the path treated it. This guide is the one handler: reading Priority and Content-Digest and Proxy-Status with the family's three gems and answering with the same Proxy-Status extended.

## The request side

Priority and Content-Digest, read together:

```ruby
require "fast/priority"
require "fast/digest"
require "fast/proxy_status"

env = {
  "REQUEST_METHOD"      => "PUT",
  "HTTP_PRIORITY"       => "u=1, i",
  "HTTP_CONTENT_DIGEST" => "sha-256=:LPJNul+wow4m6DsqxbninhsWHlwfp0JecwQzYpOLmCQ=:"
}
request_body = "hello"

priority = Fast::Priority.parse(env["HTTP_PRIORITY"] || "")
priority.urgency      # => 1
priority.incremental  # => true

sent = Fast::Digest::ContentDigest.parse(env["HTTP_CONTENT_DIGEST"] || "")
sent.empty?  # => false
sent["sha-256"] == Digest::SHA256.digest(request_body)  # => true
```

Urgency orders your upstream fetches. The digest check is the integrity gate for the upload — hash what you received, compare bytewise. An absent or unreadable field answers its field's own default (the priority defaults, the empty digest value) — never an exception, so the handler's control flow is yours. The absent-header idiom is `|| ""`; nil is a caller bug.

For the Rack-shaped details: the per-gem how-tos [parse request priority](../../gems/priority/docs/how-to-guides/parse-request-priority.md) and [validate an upload Content-Digest](../../gems/digest/docs/how-to-guides/validate-an-upload-content-digest.md).

## The upstream response

The upstream's answer arrives as a header Hash. The CDN in front of it reported itself in Proxy-Status and attached the body's digest. Read both, verify the body, extend the path:

```ruby
upstream_headers = {
  "proxy-status"   => "cdn.example.net",
  "content-digest" => "sha-256=:LPJNul+wow4m6DsqxbninhsWHlwfp0JecwQzYpOLmCQ=:"
}
upstream_body = "hello"

path = Fast::ProxyStatus.parse(upstream_headers["proxy-status"])
path.to_s  # => "cdn.example.net"

received = Fast::Digest::ContentDigest.parse(upstream_headers["content-digest"])
received["sha-256"] == Digest::SHA256.digest(upstream_body)  # => true

answer = Fast::ProxyStatus.append(upstream_headers["proxy-status"],
                                  Fast::SFV::Token.new("gateway"))
answer.to_s  # => "cdn.example.net, gateway"
```

The members run origin-closest first, user-agent-closest last, and `append` puts you last — the position your hop actually occupies. You are free to pass the verified digest through to your client, or re-digest what you transformed — that policy is yours (see [emit digests while streaming](../../gems/digest/docs/how-to-guides/emit-digests-while-streaming.md)).

## When the path fails

The CDN could not reach the origin, and said so in the field your handler can read:

```ruby
failed_headers = { "proxy-status" => "cdn.example.net; error=connection_timeout" }

path = Fast::ProxyStatus.parse(failed_headers["proxy-status"])
path.first.error  # => #<Fast::SFV::Token "connection_timeout">
Fast::ProxyStatus.recommended_status("connection_timeout")  # => 504

answer = Fast::ProxyStatus.append(failed_headers["proxy-status"],
                                  Fast::SFV::Token.new("gateway"))
answer.to_s  # => "cdn.example.net;error=connection_timeout, gateway"
```

The error parameter is one of the registry's 32 names, and the registry also recommends the HTTP status each name answers — enough to translate a failing hop into a response code without inventing your own mapping. A malformed upstream Proxy-Status never fails your response: `append` starts a fresh list rather than raising. For more: [append yourself to Proxy-Status](../../gems/proxy_status/docs/how-to-guides/append-yourself-to-proxy-status.md) and the [proxy error types reference](../../gems/proxy_status/docs/reference/proxy-error-types.md).

## What this guide did not cover

- The single-field depth — Rack env details, streaming digests and trailers, Proxy-Status trailer promotion, Cache-Status monitoring — lives in each gem's own how-to guides.
- The [family map](../reference/family-map.md) for the whole family's shape.
- The [explanations](../explanation/why-lenient-parse-strict-emit.md) for the design choices behind the handler.
