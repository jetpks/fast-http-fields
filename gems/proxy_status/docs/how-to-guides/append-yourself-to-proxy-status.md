# Append your proxy to Proxy-Status

Task-oriented; assumes you know what Proxy-Status is (see the [tutorial](../tutorials/diagnostics-fields.md)). No promote content (see [Promote a Proxy-Status trailer](promote-a-proxy-status-trailer.md)), no Cache-Status content (see [Read Cache-Status for monitoring](read-cache-status-for-monitoring.md)).

## Read the response's field

The upstream response's Proxy-Status is a response field: your stack hands it to you as the received response's headers, a String when present and nil when absent (in Rack's response-header shape, lowercase field names). The gem takes no Rack dependency; the examples use a plain Hash standing in for the received response's headers.

```ruby
received = { "content-type" => "text/plain",
            "proxy-status" => "revproxy1.example.net, ExampleCDN" }

field = Fast::ProxyStatus.parse(received["proxy-status"] || "")
field.size                                    # => 2
field.first.value == "revproxy1.example.net"  # => true
```

The absent field: pass the empty String and read the empty value:

```ruby
received = { "content-type" => "text/plain" }
Fast::ProxyStatus.parse(received["proxy-status"] || "").empty?  # => true
```

## Append your member

"When adding a value to the Proxy-Status field, intermediaries SHOULD preserve the existing members of the field to allow debugging of the entire chain of intermediaries handling the request unless explicitly configured to remove them (e.g., to prevent internal network details from leaking; see Section 4)". `append` answers a NEW frozen value with your member as the LAST — closest to the user agent:

```ruby
upstream = "revproxy1.example.net, ExampleCDN"
field = Fast::ProxyStatus.append(upstream,
                                  Fast::SFV::Token.new("MyProxy"),
                                  { "error" => Fast::SFV::Token.new("connection_timeout") })
field.size        # => 3
field.to_s        # => "revproxy1.example.net, ExampleCDN, MyProxy;error=connection_timeout"
field.last.value  # => #<Fast::SFV::Token "MyProxy">
```

The two identifier forms: a plain String emits quoted, a Token bare:

```ruby
Fast::ProxyStatus.append(nil, "My Proxy").to_s                # => "\"My Proxy\""
Fast::ProxyStatus.append(nil, Fast::SFV::Token.new("MyProxy")).to_s  # => "MyProxy"
```

The upstream forms:

- nil — a fresh list
- a String — one field value
- an Array of the field's lines — combined per RFC 9651 §4.2 before parsing
- a held `Fast::ProxyStatus` reused as held (no re-parse)

```ruby
Fast::ProxyStatus.append("!!", Fast::SFV::Token.new("MyProxy")).to_s  # => "MyProxy"
Fast::ProxyStatus.append(%w[a b], Fast::SFV::Token.new("c")).to_s     # => "a, b, c"
```

The answer re-emits the whole list canonically — non-canonical spacing normalizes (`Fast::ProxyStatus.append("a;x=1 ,  b", Fast::SFV::Token.new("c")).to_s  # => "a;x=1, b, c"`), and the held value is never mutated.

## Add parameters to your member

§2.1's five parameters with their sections' types:

- `error` — §2.1.1 a Token
- `next-hop` — §2.1.2 a String or Token
- `next-protocol` — §2.1.3 a Token or Byte Sequence
- `received-status` — §2.1.4 an Integer
- `details` — §2.1.5 a plain String

The error parameter and the registry behind it: the recommended status is a SHOULD for the sender — "When generating an HTTP response containing the error, its HTTP status code SHOULD be set to the recommended HTTP status code" — never a bound the library enforces:

```ruby
Fast::ProxyStatus.recommended_status("connection_timeout")  # => 504
Fast::ProxyStatus.response_only?("connection_timeout")      # => true
```

Extra parameters belong to the error type that defines them: "Their use, like all parameters, is optional. As a result, if an extra parameter is used with a proxy error type for which it is not defined, it will be ignored". Two entries that carry them: `dns_error` (rcode, info-code), `tls_alert_received` (alert-id, alert-message), `http_request_error` (status-code, status-phrase), and the five size/coding entries — see [The proxy error type registry](../reference/proxy-error-types.md).

Parameters can leak topology ("to prevent internal network details from leaking"; §4); see [Why diagnostics preserve unknown members](../explanation/diagnostic-leniency.md).

## Send the field on the response

The field value is `#to_s` — the canonical wire form. In Rack terms, the response headers Hash — plain-Hash idiom:

```ruby
field = Fast::ProxyStatus.append("revproxy1.example.net, ExampleCDN",
                                  Fast::SFV::Token.new("MyProxy"),
                                  { "error" => Fast::SFV::Token.new("connection_timeout") })

headers = { "content-type" => "text/plain",
            "proxy-status" => field.to_s }
headers["proxy-status"]
# => "revproxy1.example.net, ExampleCDN, MyProxy;error=connection_timeout"
```

`""` when nothing is held — a sender omits the field entirely. And §2's boundary: "Origin servers MUST NOT generate the Proxy-Status field" — this operation belongs to intermediaries.

## When the upstream field is absent or unreadable

- nil and malformed both start a fresh list (the sender never fails the response over an upstream field it cannot read)
- a constraint-violating upstream (a member that is not a String or Token) is treated as absent the same way

## Build the member directly

`Fast::ProxyStatus::Hop.new(identifier, params)` when you need the member object itself; construction is strict — a sender never puts garbage on the wire:

```ruby
hop = Fast::ProxyStatus::Hop.new(
  Fast::SFV::Token.new("x"),
  { "error" => Fast::SFV::Token.new("connection_timeout"), "received-status" => 502 }
)
hop.to_s  # => "x;error=connection_timeout;received-status=502"

field = Fast::ProxyStatus.new([hop])
field.to_s  # => "x;error=connection_timeout;received-status=502"
```

The identifier and the params Hash freeze IN PLACE as part of the value object — pass copies if the buffers are reused.

## What can go wrong

- A wrong upstream input type raises plain TypeError (a caller bug):

```ruby
begin
  Fast::ProxyStatus.append(5, "x")
rescue TypeError => e
  e.message  # => "a String or an Array of String field lines is required (got Integer)"
end
```

- A wrong member or parameter raises `Fast::ProxyStatus::SerializeError`:

```ruby
begin
  Fast::ProxyStatus.append(nil, 5)
rescue Fast::ProxyStatus::SerializeError => e
  e.message  # => "a member identifier must be a String or a Token, received Integer"
end

begin
  Fast::ProxyStatus.append(nil, Fast::SFV::Token.new("x"), { "error" => "str" })
rescue Fast::ProxyStatus::SerializeError => e
  e.message  # => "error: the value must be a Token, received String"
end
```

One rescue on `Fast::ProxyStatus::Error` guards the whole gem.

See [Proxy-Status API reference](../reference/proxy-status.md).
