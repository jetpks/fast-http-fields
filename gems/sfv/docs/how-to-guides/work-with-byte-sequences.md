# Work with byte sequences

RFC 9651's Byte Sequence type carries raw bytes on the wire as
`:base64:` between colons. fast-sfv maps it to a frozen
ASCII-8BIT-tagged `String` — and the encoding tag is what
distinguishes it from every other String you will see.

## The encoding is the tag

A byte sequence parses to a `String` tagged
`Encoding::ASCII_8BIT` (BINARY); a quoted sf-string parses to a plain
UTF-8 `String`. Same class, different tag, different wire type:

```ruby
Fast::SFV.parse_item(":aGVsbG8=:").value # => "hello"
Fast::SFV.parse_item(":aGVsbG8=:").value.encoding # => Encoding::ASCII_8BIT
Fast::SFV.parse_item("\"hello\"").value.encoding # => Encoding::UTF_8
```

The parse result is frozen, like every value fast-sfv answers:

```ruby
Fast::SFV.parse_item(":aGVsbG8=:").value.frozen? # => true
```

On the emit side the same tag decides the form — a binary-tagged
`String` emits `:base64:`, a UTF-8 `String` emits quoted:

```ruby
Fast::SFV.serialize_item(Fast::SFV::Item.new("foo".b, {})) # => ":Zm9v:"
Fast::SFV.serialize_item(Fast::SFV::Item.new("foo", {})) # => "\"foo\""
```

Base64 padding is canonical on emit; the parse accepts unpadded,
over-padded and dirty-padded input alike (the decode synthesizes the
padding), so `:aGVsbG8:` and `:aGVsbG8=:` are the same five bytes.

## The digest idiom

The reason byte sequences are plain binary `String`s: a digest you
just computed compares equal, bytewise, with the one that arrived on
the wire — no unwrapping, no conversion:

```ruby
require "digest"

body = "the request body"
wire = "sha-256=:#{[Digest::SHA256.digest(body)].pack("m0")}:"
parsed = Fast::SFV.parse_dict(wire)
parsed["sha-256"].value == Digest::SHA256.digest(body) # => true
Fast::SFV.serialize_dict(parsed) # => "sha-256=:a16syA8TNo8B4hB5NcatrM1YzaOnCcwvrr4pwBariWI=:"
```

`Digest::SHA256.digest` answers an ASCII-8BIT `String`, the parse
answers an ASCII-8BIT `String`, and `String#==` compares bytes — the
idiom works in both directions, and a re-emit round-trips to the
canonical padded form, as the last line shows.

The parse also forces UTF-8 on the values that are text — string
content, dictionary keys and display strings arrive UTF-8 whatever
the input `String`'s own tag was. A byte sequence is the only value
that is always BINARY; the one other way a BINARY value can reach you
is a token sliced out of a binary-tagged input, because `Token` is a
`String` subclass and keeps the tag of the bytes it was sliced from —
the next section is that corner.

## The class is read before the encoding

Because a `Token` IS a `String`, the serializer reads the class
before the encoding: a binary-tagged `Token` still emits bare — the
token class is the wire-type tag, the encoding is not:

```ruby
Fast::SFV::Token.new("foo".b).class # => Fast::SFV::Token
Fast::SFV.serialize_item(Fast::SFV::Item.new(Fast::SFV::Token.new("foo".b), {})) # => "foo"
```

Only a plain binary-tagged `String` is a byte sequence. If you meant
to send the bytes of a token-shaped string, tag the `String` and do
not wrap it in a `Token`:

```ruby
Fast::SFV.serialize_item(Fast::SFV::Item.new("foo".b, {})) # => ":Zm9v:"
```

## Serializers read bytewise

The emit path walks values with `getbyte` and appends whole byte
ranges, so the input's encoding tag matters only where the mapping
says it does. A UTF-8 `String` whose bytes are all ASCII emits quoted
just the same; a UTF-8 `String` with high bytes is not silently
converted — an sf-string may only carry SP and printable ASCII, so
the strict emit raises. Text with non-ASCII content is the Display
String type's job, and it percent-encodes:

```ruby
Fast::SFV.serialize_item(Fast::SFV::Item.new("plain ascii", {})) # => "\"plain ascii\""
Fast::SFV.serialize_item(Fast::SFV::Item.new("fü", {})) # raises Fast::SFV::SerializeError
Fast::SFV.serialize_item(Fast::SFV::Item.new(Fast::SFV::DisplayString.new("fü"), {})) # => "%\"f%c3%bc\""
```

## Where to go next

- [Type mapping — RFC 9651 to Ruby](../reference/type-mapping.md) —
  all nine wire types against their Ruby values.
- [Design decisions in fast-sfv](../explanation/design-decisions.md) —
  the ASCII-8BIT ruling and the wrapper alternative that was rejected.
- [Getting started with fast-sfv](../tutorials/getting-started.md) —
  the walkthrough this guide assumes.
