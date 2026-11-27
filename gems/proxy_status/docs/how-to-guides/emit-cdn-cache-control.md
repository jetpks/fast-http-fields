# Emit CDN-Cache-Control

## Build the field

`Fast::TargetedCacheControl.new(members)` — a Hash of directive key => bare value; construction is strict, the emit canonical:

```ruby
field = Fast::TargetedCacheControl.new({ "max-age" => 600, "no-store" => true })
field.size  # => 2
field.to_s  # => "max-age=600, no-store"
```

`""` when nothing is held — a sender omits the field entirely, §3.1's own advice: "'none' is not a registered cache directive; it is here to avoid sending a header field with an empty value, which would be ignored".

## The five MUST-implement directives

"Caches that use a targeted field MUST implement the semantics of the following cache directives: max-age, must-revalidate, no-store, no-cache, private". The gem pins their types in `DIRECTIVES` — max-age an Integer, must-revalidate and no-store Boolean true, no-cache and private Boolean true or a String (the types from RFC 9111 §5.2.2: max-age "an integer number of seconds", must-revalidate and no-store no argument, no-cache and private a field-name list in a quoted string):

```ruby
field = Fast::TargetedCacheControl.new(
  { "max-age" => 600, "must-revalidate" => true, "no-store" => true,
    "no-cache" => "Set-Cookie, Foo", "private" => true }
)
field.to_s  # => "max-age=600, must-revalidate, no-store, no-cache=\"Set-Cookie, Foo\", private"
```

The `none` convention, §3.1's own example pair:

```text
Cache-Control: no-store
CDN-Cache-Control: none
```

On the wire `none` is a valueless unregistered directive:

```ruby
field = Fast::TargetedCacheControl.parse("none")
field["none"]   # => true
field.to_s      # => "none"
field.violating # => []
```

## The type mapping

"cache directives that have no value will be mapped to a Boolean … When the value is a quoted-string, it will be mapped to a String … , and when it is a token, it will map to a Token … , an Integer … , or a Decimal … , depending on the content of the value". The gem reads that mapping on parse and enforces it on emit.

"string values whose first character is not alphabetic or '*' MUST be generated as Strings so that they are not mistaken for other types". It holds structurally: a plain String always emits quoted, and a Token's own grammar refuses the form at its construction — no check of the class's own is needed:

```ruby
Fast::TargetedCacheControl.new({ "x-custom" => "9abc" }).to_s                        # => "x-custom=\"9abc\""
Fast::TargetedCacheControl.new({ "x-custom" => Fast::SFV::Token.new("foo") }).to_s    # => "x-custom=foo"
```

The valueless form and its canonicalization: an explicit `?1` canonicalizes valueless, `?0` round-trips:

```ruby
Fast::TargetedCacheControl.parse("no-store=?1").to_s  # => "no-store"
Fast::TargetedCacheControl.parse("no-store=?0").to_s  # => "no-store=?0"
```

Parameters on directives are ignored — "Parameters received on cache directives are to be ignored, unless other handling is explicitly specified" — the class never builds them and preserves what it receives in the raw member data (see [The Targeted Cache Control boundary](../explanation/the-targeted-cache-control-boundary.md)).

## Send it on the response

§3.1's first example pair:

```text
Cache-Control: max-age=60, s-maxage=120
CDN-Cache-Control: max-age=600
```

The CDN sees 600, other shared caches 120, the rest 60. The plain-Hash response idiom with `FIELD_NAME`:

```ruby
headers = { "cache-control" => "max-age=60, s-maxage=120",
            Fast::TargetedCacheControl::FIELD_NAME =>
              Fast::TargetedCacheControl.new({ "max-age" => 600 }).to_s }
headers["CDN-Cache-Control"]  # => "max-age=600"
```

CDN caches "will typically forward this header so that downstream CDN caches can use it as well. However, they MAY remove it when this is undesirable" — forwarding is cache behavior, not this class's.

## What you receive back

The flagged leniency: a violating value is preserved and flagged:

```ruby
field = Fast::TargetedCacheControl.parse("max-age=60.5")
field["max-age"]  # => 60.5
field.violating   # => ["max-age"]
field.to_s        # => "max-age=60.5"
```

"Implementations SHOULD NOT consume values that violate these inferred constraints" — check `violating` before consuming. A malformed or empty field is ignored entirely — §2.1's MUST.

The refuse-on-emit example:

```ruby
begin
  Fast::TargetedCacheControl.new({ "max-age" => 1.5 })
rescue Fast::TargetedCacheControl::SerializeError => e
  e.message  # => "max-age: the value must be an Integer, received 1.5"
  e.offset   # => 0
end
```

See [Targeted Cache Control API reference](../reference/targeted-cache-control.md), [The cache directive table](../reference/cache-directives.md), and [Targeted cache control and the age penalty](../explanation/age-penalty.md).
