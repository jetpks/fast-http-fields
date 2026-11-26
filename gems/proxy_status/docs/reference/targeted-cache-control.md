# Targeted Cache Control API reference

The definitive page for the `Fast::TargetedCacheControl` surface. The directive table has its own page (see [The cache directive table](cache-directives.md)).

## The module

`Fast::TargetedCacheControl`, loaded by `require "fast/proxy_status"`; does NOT include the List engine — a Dictionary's members are key-value and its leniency is per-directive.

`Fast::TargetedCacheControl::FIELD_NAME` is `"CDN-Cache-Control"` — §3's registered instance; the class carries NO "-Cache-Control" suffix matcher.

## Parsing

`parse(input)` → the frozen value object; §2.1's own leniency split: a field that is empty or fails to parse is the ENTIRE field ignored ("If a targeted field in a given response is empty, or a parsing error is encountered, that field MUST be ignored by the cache") — the shared frozen empty value, the same answer an absent field gives; while a member whose value violates the inferred constraints is PRESERVED and FLAGGED.

Parameters on directives are ignored: never a flag, preserved in the raw member data, re-emitted by a round-trip.

`parse!(input)` — strict: the wrapped Dictionary failure, then §2.1's inferred constraints, the first offender in Dictionary order raised positioned at that member's VALUE (just past the "="; the key's end for the valueless form; the LAST occurrence of a duplicated key).

`valid?(input)` — the boolean mirror.

Input: a String or an Array of field lines, combined with ", " — duplicate keys: last value wins, first position kept:

```ruby
combined = Fast::TargetedCacheControl.parse(["a=1", "a=2"])
combined["a"]  # => 2
combined.to_s  # => "a=2"
```

## The value object

Readers: `members` (the frozen ordered Hash of directive key => `Fast::SFV::Item` or `InnerList`, parameters preserved), `keys` (frozen, held order), `[](key)` (the bare value — an inner list member's raw view is its items), `key?`, `size`, `empty?`, `each` (yields key and bare value).

`violating` — §2.1's SHOULD-NOT-consume set: the keys whose values violate the inferred constraints, in held order, `[]` when clean; data, never a wire change.

`to_s` — the canonical RFC 9651 §4.1.2 Dictionary serialization, `""` when empty; a parsed value re-emits faithfully, violating values included, the explicit `?1` canonicalizing valueless.

`==`/`eql?`/`hash` canonical within the class; `inspect` `#<Fast::TargetedCacheControl <wire>>`:

```ruby
Fast::TargetedCacheControl.parse("max-age=600").inspect
# => "#<Fast::TargetedCacheControl max-age=600>"
```

The reader set on one fence:

```ruby
field = Fast::TargetedCacheControl.parse("max-age=600, no-store")
field.keys          # => ["max-age", "no-store"]
field.key?("max-age")  # => true
field["no-cache"]   # => nil
field.size          # => 2
collected = []; field.each { |key, value| collected << [key, value] }; collected  # => [["max-age", 600], ["no-store", true]]
```

The inner-list raw view:

```ruby
inner_list = Fast::TargetedCacheControl.parse("a=(1 2)")
inner_list["a"].map(&:value)  # => [1, 2]
inner_list.violating          # => ["a"]
inner_list.to_s               # => "a=(1 2)"
```

## Construction

`Fast::TargetedCacheControl.new(members = {})` — a Hash of directive key => bare value: every value one of the five inferred types (a Boolean, an Integer, a Float, a Token or a plain String), a known directive's value carrying its section's type, the keys Structured Fields keys; values freeze in place; each member wraps as an Item with no parameters; the empty Hash builds the empty value.

```ruby
Fast::TargetedCacheControl.new({ "max-age" => 600, "no-store" => true }).to_s
# => "max-age=600, no-store"

Fast::TargetedCacheControl.new({ "x-custom" => "9abc" }).to_s  # => "x-custom=\"9abc\""
```

## Errors

`Fast::TargetedCacheControl::Error < Fast::ProxyStatus::Error`, nesting its own `ParseError`/`SerializeError`, both with `#offset`.

## Requirements

As Proxy-Status's (the one gem, the one runtime dependency).
