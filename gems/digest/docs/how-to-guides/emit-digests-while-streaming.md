# Emit digests while streaming

Hash content as it streams with the stdlib, build the field, send it as a header or a trailer, and know the trailer cautions.

## Hash as the content streams

The stdlib hashes incrementally; the gem's field construction takes the finished bytes — compute while you write, construct at the end:

```ruby
require "digest"
require "fast/digest"

hasher = Digest::SHA256.new
["{\"hello\"", ": ", "\"world\"}\n"].each { |chunk| hasher.update(chunk) }

field = Fast::Digest::ReprDigest.new("sha-256" => hasher.digest)
field.to_s  # => "sha-256=:RK/0qy18MlBSVnWgjwz6lZEWjP/lF5HF9bvEF8FabDg=:"
```

`Fast::Digest.compute` is the one-shot form of the same stdlib call (`lib/fast/digest/registry.rb:100-110`); §6.4's own rationale for trailers — "it allows hashing of bytes as they are sent" (`rfc9530.txt:637-639`).

## Build the field

```ruby
require "digest"
require "fast/digest"

body = "{\"hello\": \"world\"}\n"

repr = Fast::Digest::ReprDigest.of("sha-256", body)
repr.to_s  # => "sha-256=:RK/0qy18MlBSVnWgjwz6lZEWjP/lF5HF9bvEF8FabDg=:"

field = Fast::Digest::ReprDigest.new("sha-256" => Digest::SHA256.digest(body))
field == repr  # => true
```

Construction is strict: the value must be a String tagged ASCII-8BIT — `hasher.digest` already is (`lib/fast/digest/fields.rb:258-278`).

The value String is frozen IN PLACE as part of the value object — pass a copy if the buffer is reused (`lib/fast/digest/fields.rb:266-268`; `test/fast/digest/fields.rb:298-304`).

## Send it as a header

The field value is `#to_s` — the canonical wire form, `""` when nothing is held (a sender omits the field entirely, `lib/fast/digest/fields.rb:307-316`). In Rack terms, the response headers Hash:

```ruby
require "fast/digest"

body = "{\"hello\": \"world\"}\n"
field = Fast::Digest::ReprDigest.of("sha-256", body)

headers = { "content-type" => "application/json",
            "repr-digest" => field.to_s }
headers["repr-digest"]
# => "sha-256=:RK/0qy18MlBSVnWgjwz6lZEWjP/lF5HF9bvEF8FabDg=:"
```

## Send it as a trailer

Both Integrity fields "can be sent in a trailer section" and then "MAY be merged into the header section" (§2/§3, `rfc9530.txt:326-328,386-392`). The RFC's own B.11 wire form (the chunked message, `rfc9530.txt:1452-1470`, Figure 30 at 1471) — in the response content below, the string "\r\n" represents the CRLF bytes (`rfc9530.txt:1446-1447`):

NOTE: '\' line wrapping per RFC 8792 (`rfc9530.txt:1454`)

```
HTTP/1.1 200 OK
Content-Type: application/json
Transfer-Encoding: chunked
Trailer: Repr-Digest

8\r\n
{"hello"\r\n
8\r\n
: "world\r\n
3\r\n
"}\n\r\n
0\r\n
Repr-Digest: \
sha-256=:RK/0qy18MlBSVnWgjwz6lZEWjP/lF5HF9bvEF8FabDg==:\r\n
```

Figure 30: Chunked Response with Digest (`rfc9530.txt:1471`)

`Trailer: Repr-Digest` advertises the field in the headers; the field arrives on the zero-chunk line. The digest value is identical to B.1's because Repr-Digest is independent of transfer codings (B.11, `rfc9530.txt:1441-1446`).

The receiving side of a merged trailer: the Array-of-lines entry point (see the [content validation guide](validate-an-upload-content-digest.md)'s combining contract). No Rack trailer API is claimed — the trailer plumbing belongs to the server/framework; the gem's boundary is the field value.

## The trailer cautions

- "intermediaries are explicitly allowed to drop any trailer" (`rfc9530.txt:630-632`).
- "field-values are received after the content. Eager processing of content before the trailer section prevents digest validation, possibly leading to processing of invalid data" (`rfc9530.txt:633-636`).
- The MICE-style reverse-order caveat: a second, hash-independent content encoding applied after the digest was computed means the trailer arrives too late for streaming validation (`rfc9530.txt:639-645`).

The corpus's own B.5/B.11/C.1 values carry doubled base64 padding (`==:`) — an erratum; the gem parses them to the same bytes and re-emits the single-padding canonical form:

```ruby
require "fast/digest"

Fast::Digest::ReprDigest.parse("sha-256=:RK/0qy18MlBSVnWgjwz6lZEWjP/lF5HF9bvEF8FabDg==:").to_s
# => "sha-256=:RK/0qy18MlBSVnWgjwz6lZEWjP/lF5HF9bvEF8FabDg=:"
```

See [What digests do and do not protect](../explanation/security-posture.md).
