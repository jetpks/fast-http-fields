# Promote a Proxy-Status trailer into the header

## Why a proxy sends a trailer at all

"Proxy-Status MAY be sent as an HTTP trailer field" and "Proxy-Status SHOULD NOT be sent as a trailer field unless it is not possible to send it in the header section"; "To allow recipients to reconstruct the relative ordering of Proxy-Status members conveyed in trailer fields with those conveyed in header fields, an intermediary MUST NOT send Proxy-Status as a trailer field unless it has also generated a Proxy-Status header field with the same member (although potentially different parameters) in that message".

§2's own worked story:

```text
The proxy 'ThisProxy' receives:

  Proxy-Status: SomeOtherProxy

It appends itself to the header:

  Proxy-Status: SomeOtherProxy, ThisProxy

And appends the trailer:

  Proxy-Status: ThisProxy; error=read_timeout
```

## The promotion algorithm

A client MAY promote the Proxy-Status trailer field into a header field by following these steps: 1. For each member trailer_member of the Proxy-Status trailer field value: 1. Let header_member be the first (leftmost) value of the Proxy-Status header field value, comparing the String or Token character by character without consideration of parameters. 2. If no matching header_member is found, continue processing the next trailer_member. 3. Replace header_member with trailer_member in its entirety, including any parameters. 2. Remove the Proxy-Status trailer field if empty.

`Fast::ProxyStatus.promote(header, trailer)` implements the steps exactly; both arguments read as `parse` reads them (nil, a String, an Array of lines, a held value; a malformed field is treated as absent). Answers a frozen `Fast::ProxyStatus::Promotion`.

## Promote the field

```ruby
promoted = Fast::ProxyStatus.promote("SomeOtherProxy, ThisProxy", "ThisProxy; error=read_timeout")
promoted.header.to_s  # => "SomeOtherProxy, ThisProxy;error=read_timeout"
promoted.trailer      # => nil
```

## What each answer looks like

The unmatched member stays in the trailer:

```ruby
promoted = Fast::ProxyStatus.promote("A, B", "C; error=x")
promoted.header.to_s   # => "A, B"
promoted.trailer.to_s  # => "C;error=x"
```

Replacement is in its ENTIRETY, parameters included — the header member's own parameters do not survive:

```ruby
promoted = Fast::ProxyStatus.promote("ThisProxy;a=1, Other", "ThisProxy")
promoted.header.to_s  # => "ThisProxy, Other"
promoted.trailer      # => nil
```

The match is on the value characters across the String and Token forms:

```ruby
promoted = Fast::ProxyStatus.promote("\"ThisProxy\", Other", "ThisProxy;x=1")
promoted.header.to_s  # => "ThisProxy;x=1, Other"
```

The LEFTMOST match wins:

```ruby
promoted = Fast::ProxyStatus.promote("A, B, A", "A;x=1")
promoted.header.to_s  # => "A;x=1, B, A"
```

Trailer members are processed in order against the header as it stands — sequential replacement:

```ruby
promoted = Fast::ProxyStatus.promote("A, B", "A;x=1, A;y=2")
promoted.header.to_s  # => "A;y=2, B"
promoted.trailer      # => nil
```

The Promotion object: `#header` nil exactly when the header input was nil (the algorithm only replaces, never adds), `#trailer` nil exactly when nothing remains; `inspect` and class-checked equality:

```ruby
promoted = Fast::ProxyStatus.promote("A, B", "B;x=1")
promoted.inspect
# => "#<Fast::ProxyStatus::Promotion header=#<Fast::ProxyStatus A, B;x=1>, trailer=nil>"
promoted == Fast::ProxyStatus.promote("A, B", "B;x=1")  # => true
```

## When there was no header field

```ruby
no_header = Fast::ProxyStatus.promote(nil, "A;x=1")
no_header.header          # => nil
no_header.trailer.to_s    # => "A;x=1"
```

An empty String header is a present-but-empty field (`Fast::ProxyStatus.promote("", "A;x=1").header.empty?  # => true`).

An absent or unreadable trailer is removed, the header untouched:

```ruby
Fast::ProxyStatus.promote("A, B", nil).trailer   # => nil
unreadable = Fast::ProxyStatus.promote("A, B", "!!")
unreadable.trailer        # => nil
unreadable.header.to_s    # => "A, B"
```

## Lines and held values

The Array-of-lines form on either side, combined per RFC 9651 §4.2 before the walk; held `Fast::ProxyStatus` values accepted on both sides:

```ruby
lines = Fast::ProxyStatus.promote(%w[SomeOtherProxy ThisProxy], ["ThisProxy; error=read_timeout"])
lines.header.to_s  # => "SomeOtherProxy, ThisProxy;error=read_timeout"

objects = Fast::ProxyStatus.promote(Fast::ProxyStatus.parse("A, B"), Fast::ProxyStatus.parse("B;x=1"))
objects.header.to_s  # => "A, B;x=1"
```

TypeError for a wrong input type on either side (`Fast::ProxyStatus.promote(5, "A")`).

See [Proxy-Status API reference](../reference/proxy-status.md) and the trailer cautions in [Why diagnostics preserve unknown members](../explanation/diagnostic-leniency.md).
