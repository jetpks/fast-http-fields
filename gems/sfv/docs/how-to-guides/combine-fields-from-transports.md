# Combine fields from h1, h2, h3 and Rack

The field-value grammar is transport-agnostic: what varies is the
shape the transport hands you — separate lines, joined lines,
lowercase names. The rule on the way in is always RFC 9651 §4.2's:
combine same-named lines into one comma-separated value, then parse.
The rule on the way out is always RFC 9651 §4.1's: one canonical
single-line value, legal in h1, h2 and h3 alike.

## What each transport hands you

HTTP/1.1 hands you one field as several field lines, and the field
names are matched case-insensitively — the combining is the
recipient's job:

```text
GET / HTTP/1.1
Host: example.com
Priority: u=3
Priority: u=1, i
```

Line folding is obsolete in HTTP/1.1; a conforming stack either
rejects a folded line or unfolds it before the value reaches you, so
what you parse is what arrived. HTTP/2 and HTTP/3 lowercase the field
names on the wire, and same-named lines arrive as separate frames the
recipient combines into one value by the same rule — the names being
lowercase changes nothing for the value parser, which never looks at
a field name. Rack hands you the finished joins: the request
environment carries the field under `HTTP_` plus the uppercased,
underscored name, with same-named lines already joined with `", "` —
the RFC's own combining form.

## Parse all of it

The h1 shape — several lines for one field — is the Array entry point:

```ruby
lines = ["u=3", "u=1, i"]
Fast::SFV.parse_dict(lines).keys # => ["u", "i"]
Fast::SFV.parse_dict(lines)["u"].value # => 1
```

The dictionary keeps the key's first position and takes its last
value, so the two `u` members combine to one key holding `1`.

The h2/h3 shape — lowercase name, one already-combined value — and
the Rack request shape — an `HTTP_`-prefixed environment key holding
the same combined String — are the String entry point:

```ruby
fields = { "priority" => "u=3, u=1, i" }
Fast::SFV.parse_dict(fields["priority"]).keys # => ["u", "i"]

env = { "HTTP_PRIORITY" => "u=3, u=1, i" }
Fast::SFV.parse_dict(env["HTTP_PRIORITY"])["u"].value # => 1
```

Rack does not need to be a dependency for this: the environment is a
plain `Hash` of `String` keys, and fast-sfv takes the value as a
plain String. Nothing here requires Rack, a middleware, or a
transport library.

## Emit one canonical line

On the sending side, serialize to ONE line and set the field once.
RFC 9651 §4.1's canonical form is a single field line with no
trailing whitespace, no folding, and the members in the order of the
structure — legal as-is in h1, h2 and h3:

```ruby
Fast::SFV.serialize_dict("u" => Fast::SFV::Item.new(3, {}), "i" => Fast::SFV::Item.new(true, {})) # => "u=3, i"
Fast::SFV.serialize_list([Fast::SFV::Item.new(1, {}), Fast::SFV::Item.new(2, {}), Fast::SFV::Item.new(3, {})]) # => "1, 2, 3"
```

A Rack response header is the same single-line rule — set the field
once, with the field name your API spells (an h2 or h3 stack
lowercases it on the wire, since those transports require lowercase
field names):

```ruby
headers = {}
headers["Priority"] = Fast::SFV.serialize_dict("u" => Fast::SFV::Item.new(3, {}))
headers["Priority"] # => "u=3"
```

One caveat on multi-line emission: an empty List or Dictionary
serializes to `nil`, which means the field is omitted entirely —
check for `nil` before setting a header, or you would send the
String `"nil"`:

```ruby
Fast::SFV.serialize_list([]) # => nil
```

## Where to go next

- [Handle multi-line fields](handle-multi-line-fields.md) — the
  combining rule and the members that may not be split.
- [Parse or emit?](parse-vs-emit.md) — the decision guide both sides
  of this page lean on.
- [Fast::SFV — API reference](../reference/api.md) — the
  String-or-Array input contract, per entry point.
