# The cache directive table

The definitive page for `Fast::TargetedCacheControl::DIRECTIVES`, `FIELD_NAME` and `INFERRED`.

## The table as data

§2.2's MUST-implement five, pinned as frozen public data: the types from §2.1's own mapping and the Cache-Control sections it cites — max-age "an integer number of seconds" (RFC 9111 §5.2.2.1), must-revalidate and no-store no argument (§5.2.2.2/§5.2.2.5), no-cache and private "a field-name list" in a quoted string (§5.2.2.4/§5.2.2.7). The table never gates a parse — an unknown directive parses, is preserved and round-trips ("unrecognized extension directives are ignored"):

```ruby
Fast::TargetedCacheControl::DIRECTIVES
# => {"max-age" => "an Integer", "must-revalidate" => "Boolean true", "no-store" => "Boolean true",
#     "no-cache" => "Boolean true or a String", "private" => "Boolean true or a String"}
```

## The five directives

- `max-age` — an Integer; RFC 9111 §5.2.2.1 — wire: `max-age=600`
- `must-revalidate` — Boolean true; §5.2.2.2 — wire: `must-revalidate`
- `no-store` — Boolean true; §5.2.2.5 — wire: `no-store`
- `no-cache` — Boolean true or a String; §5.2.2.4 — wire: `no-cache` / `no-cache="Set-Cookie, Foo"`
- `private` — Boolean true or a String; §5.2.2.7 — wire: `private` / `private="Foo, Bar"`

## FIELD_NAME and the suffix rule

```ruby
Fast::TargetedCacheControl::FIELD_NAME  # => "CDN-Cache-Control"
```

"By convention, targeted fields have the suffix '-Cache-Control', e.g., 'ExampleCDN-Cache-Control'. However, this suffix MUST NOT be used on its own to identify targeted fields; it is only a convention". The class carries no suffix matcher:

```ruby
Fast::TargetedCacheControl.respond_to?(:targeted_name?)  # => false
```

See [The Targeted Cache Control boundary](../explanation/the-targeted-cache-control-boundary.md).

## The inferred types

`Fast::TargetedCacheControl::INFERRED` — the wording the errors carry for a value outside §2.1's mapping: "one of the inferred types (a Boolean, a String, a Token, an Integer or a Decimal)":

```ruby
Fast::TargetedCacheControl::INFERRED
# => "one of the inferred types (a Boolean, a String, a Token, an Integer or a Decimal)"
```

"cache directives that have no value will be mapped to a Boolean … When the value is a quoted-string, it will be mapped to a String … , and when it is a token, it will map to a Token … , an Integer … , or a Decimal … , depending on the content of the value". What is OUTSIDE it: an inner list, a Byte Sequence, a Date, a Display String.

## Unknown and future directives

The passthrough contract:

```ruby
field = Fast::TargetedCacheControl.parse("x-extension=foo, max-age=600")
field.violating       # => []
field["x-extension"]  # => #<Fast::SFV::Token "foo">
```

Unknown extension directives are preserved and round-trip untouched.
