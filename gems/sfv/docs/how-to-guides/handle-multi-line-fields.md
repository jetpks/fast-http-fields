# Handle multi-line fields

An HTTP field can arrive as several field lines — one field, many
lines. RFC 9651 §4.2's combining rule says the recipient must combine
every line in the same section whose field name case-insensitively
matches into ONE comma-separated field value before parsing.

## One field, many lines

What the transport hands you as several lines, fast-sfv takes as one
Array. This is one field, two lines:

```text
Example-List: 2;foourl="https://foo.example.com/"
Example-List: 7, tooter
```

Join the lines with `", "` — the separator the RFC's own combining
produces — or hand the Array over and let fast-sfv do it:

```ruby
["1", "2", "3"].join(", ") # => "1, 2, 3"
Fast::SFV.parse_list(["1", "2", "3"]).map(&:value) # => [1, 2, 3]
Fast::SFV.parse_dict(["a=1", "b=2"]).keys # => ["a", "b"]
```

Every entry point takes the String form or the Array form —
`parse_item`, `parse_list` and `parse_dict` are the same parse either
way, and so are the `valid_*?` mirrors. An Array member that is not a
String raises `TypeError` before any parse runs, and two lines that
combine to a value of the wrong shape fail the asked shape — two Item
lines combine to `1, 2`, which is a List:

```ruby
Fast::SFV.valid_list?(["1", "2", "3"]) # => true
Fast::SFV.valid_dict?(["a=1", "b=2"]) # => true
Fast::SFV.valid_item?(["1", "2"]) # => false
Fast::SFV.parse_item(["1", "2"]) # raises Fast::SFV::ParseError
```

## When the lines came from Rack

Rack already hands you the joined value — `env` carries the field
under `HTTP_` plus the uppercased, underscored field name, and
same-named lines are joined with `", "` — which is exactly the RFC's
combining form, so the String entry point is the one to use there.
See [Combine fields from h1, h2, h3 and Rack](combine-fields-from-transports.md).

## The members that may not be split

The combining rule is safe because Lists and Dictionaries separate
members with commas. A single member split across lines is not:

- Tokens, integers, decimals and byte sequences cannot be split — the
  inserted comma fails the parse.
- A string split across lines does not fail: the comma becomes part
  of the string content, which is why RFC 9651 §4.2 calls the result
  unpredictable (an upstream intermediary may have combined the lines,
  outside your control).

```ruby
Fast::SFV.parse_item(["to", "oter"]) # raises Fast::SFV::ParseError
Fast::SFV.parse_list(["\"foo", "bar\""]).map(&:value) # => ["foo, bar"]
```

The parser is allowed to fail a multi-line field whose lines do not
parse as that field; when the parse fails, RFC 9651 §4.2 requires the
whole field be ignored or the whole message treated as malformed —
fast-sfv takes the strict branch and raises, so your field policy
decides what happens next. The `valid_*?` mirrors are the boolean form
of that policy:

```ruby
Fast::SFV.valid_item?(["to", "oter"]) # => false
```

## Emit one canonical line

Serialization always answers ONE line — RFC 9651 §4.1's canonical
form, legal as a single field line in every transport. Whatever the
lines looked like on the way in, the way out is one value:

```ruby
Fast::SFV.serialize_list(Fast::SFV.parse_list(["1", "2", "3"])) # => "1, 2, 3"
Fast::SFV.serialize_dict(Fast::SFV.parse_dict(["a=1", "b=2"])) # => "a=1, b=2"
```

## Where to go next

- [Combine fields from h1, h2, h3 and Rack](combine-fields-from-transports.md) —
  what each transport hands you and how to emit back into it.
- [Fast::SFV — API reference](../reference/api.md) — the
  String-or-Array input contract, per entry point.
- [RFC 9651 vs RFC 8941](../explanation/rfc-9651-vs-8941.md) — where
  the combining rule's strictness was refined between the two RFCs.
