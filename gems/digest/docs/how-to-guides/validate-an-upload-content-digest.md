# Validate an upload's Content-Digest in Rack

This guide reads an upload's Content-Digest header in a Rack-shaped env, parses it, compares against the received bytes, and handles absence, malformed input, and multiple lines.

## Read the header

Rack exposes a request's Content-Digest header as `env["HTTP_CONTENT_DIGEST"]` (Rack's CGI-derived convention: HTTP_ + uppercased, dashes to underscores) — a String when present, nil when absent. The gem takes no Rack dependency; the examples use a plain Hash standing in for env, exactly the shape Rack hands you.

```ruby
require "fast/digest"

env = { "REQUEST_METHOD" => "PUT",
        "HTTP_CONTENT_DIGEST" => "sha-256=:RK/0qy18MlBSVnWgjwz6lZEWjP/lF5HF9bvEF8FabDg=:" }

field = Fast::Digest::ContentDigest.parse(env["HTTP_CONTENT_DIGEST"] || "")
field.keys  # => ["sha-256"]
```

The absent header: `env["HTTP_CONTENT_DIGEST"]` is nil — a caller bug for `parse` (TypeError), so pass the empty field and read the empty value:

```ruby
require "fast/digest"

env = { "REQUEST_METHOD" => "PUT" }
Fast::Digest::ContentDigest.parse(env["HTTP_CONTENT_DIGEST"] || "").empty?  # => true
```

For an upload with no content coding, content and representation data are the same bytes, so Content-Digest and Repr-Digest verify alike (B.1, `rfc9530.txt:1091-1094`); when Content-Encoding is in play they differ — Content-Digest digests the conveyed bytes, Repr-Digest the selected representation (§2 at `rfc9530.txt:282-285`, §3 at 332-343). See [Content or representation data](../explanation/content-or-representation.md).

## Parse it

`Fast::Digest::ContentDigest.parse(input)` — the recipient view, never raises on content; TypeError only for a non-String/non-Array input (`lib/fast/digest/fields.rb:158-176`).

Fail-closed, the whole-field rule: ANY member violating the Byte Sequence constraint ignores the ENTIRE field — a valid member beside a bad one drops with it (RFC 9651 §2.2; `lib/fast/digest/fields.rb:158-176`):

```ruby
require "fast/digest"

Fast::Digest::ContentDigest.parse("sha-512=:AAAA:, md5=5").empty?  # => true
Fast::Digest::ContentDigest.parse("sha-256=hello").empty?          # => true
Fast::Digest::ContentDigest.parse("").empty?                       # => true
```

An empty string is the valid empty Dictionary.

## Compare against the bytes you received

Hash what you actually received and compare bytewise — `[]` answers the bare digest bytes:

```ruby
require "digest"
require "fast/digest"

env = { "REQUEST_METHOD" => "PUT",
        "HTTP_CONTENT_DIGEST" => "sha-256=:RK/0qy18MlBSVnWgjwz6lZEWjP/lF5HF9bvEF8FabDg=:" }
request_body = "{\"hello\": \"world\"}\n"

field = Fast::Digest::ContentDigest.parse(env["HTTP_CONTENT_DIGEST"])
field["sha-256"] == Digest::SHA256.digest(request_body)  # => true
```

`field.keys` names what the sender used; unknown algorithm keys pass through as parsed — the comparison against your stdlib answer is the caller's decision (`lib/fast/digest/fields.rb:158-176`; `lib/fast/digest/registry.rb:57-61`). See [Choose hashing algorithms](choose-algorithms.md) for the multi-algorithm case.

## Absent, malformed, or ignored

Three answers: absent and malformed both answer the empty value object (fail-closed — the recipient treats what it cannot read as if the field were not sent, `rfc9651.txt:279-288`); a digest that is present but FAILS the comparison is yours to act on — "A recipient MAY ignore any or all digests. Application-specific behavior or local policy MAY set additional constraints on the processing and validation practices of the conveyed digests" (`rfc9530.txt:315-317`).

The strict view for diagnostics — `parse!` raises `Fast::Digest::ParseError` naming the member and the required shape, positioned at the member's value. For `"md5=5"`:

```ruby
require "fast/digest"

begin
  Fast::Digest::ContentDigest.parse!("md5=5")
rescue Fast::Digest::ParseError => e
  e.message  # => "md5: a Content-Digest value is a Byte Sequence: a String tagged Encoding::ASCII_8BIT (got 5)"
  e.offset   # => 4
end
```

The full message catalog lives in [API reference](../reference/api.md). When you only need a yes/no, `valid?` answers it (`lib/fast/digest/fields.rb:200-205`):

```ruby
require "fast/digest"

Fast::Digest::ContentDigest.valid?("md5=5")  # => false
```

## Multi-line and trailer-merged fields

Some stacks hand you a field split across lines — an HTTP message can carry the same field name on several lines, and a trailer merged into the header section joins them; the Array input combines with ", " exactly as RFC 9651 §4.2 requires, duplicates last-wins (`lib/fast/digest/fields.rb:209-214`):

```ruby
require "fast/digest"

Fast::Digest::ContentDigest.parse(["sha-256=:AAAA:", "md5=:BBBB:"]).keys
# => ["sha-256", "md5"]
```

When a signature covers the field, "de-duplicating digests or combining different field values" mangles what it covers — the combining here is the parse contract; what a signature sees is the caller's context (`rfc9530.txt:621-625`). See [What digests do and do not protect](../explanation/security-posture.md).
