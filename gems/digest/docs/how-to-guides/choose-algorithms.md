# Choose hashing algorithms

## What the registry knows

`Fast::Digest::ALGORITHMS` — §7.2 Table 2 pinned as frozen data, eight entries in order (`lib/fast/digest/registry.rb:24-44`):

```ruby
require "fast/digest"

Fast::Digest::ALGORITHMS.keys
# => ["sha-512", "sha-256", "md5", "sha", "unixsum", "unixcksum", "adler", "crc32c"]
```

The lookups:

```ruby
require "fast/digest"

Fast::Digest.registered?("crc32c")  # => true
Fast::Digest.status("sha-256")  # => "Active"
Fast::Digest.status("md5")  # => "Deprecated"
Fast::Digest.active?("md5")  # => false
Fast::Digest.deprecated?("md5")  # => true
```

`registered?`, `status`, `active?`, `deprecated?`, `computable?` — see [The hash algorithm registry](../reference/algorithms.md) (`lib/fast/digest/registry.rb:59-89`).

## Active, Deprecated, and your setting

Active algorithms "are suitable for many purposes and it is RECOMMENDED that applications use these algorithms" (`rfc9530.txt:490-493`); Deprecated ones "MAY be used to preserve integrity against corruption, but MUST NOT be used in a potentially adversarial setting, for example, when signing Integrity fields' values for authenticity" (`rfc9530.txt:502-505`).

The status is advisory here — it never gates a parse, an emit or a computation; md5 and sha compute exactly like the Active ones. The adversarial-setting line is the caller's judgment. See [Algorithm agility and the registry's statuses](../explanation/algorithm-agility.md).

## Multiple digests for transitions

§2's own rationale: the Dictionary type "can be used, for example, to attach multiple digests calculated using different hashing algorithms in order to support a population of endpoints with different or evolving capabilities. Such an approach could support transitions away from weaker algorithms" (`rfc9530.txt:305-312`). Appendix D's own pair as a constructed field:

```ruby
require "digest"
require "fast/digest"

hello = "{\"hello\": \"world\"}"
field = Fast::Digest::ContentDigest.new(
  "sha-256" => Digest::SHA256.digest(hello),
  "md5" => Digest::MD5.digest(hello)
)
field.to_s
# => "sha-256=:X48E9qOokqqrvdts8nOJRJN3OWDUoyWxBf7kbu9DBPE=:, md5=:Sd/dVLAcvNLSq16eXua5uQ==:"
```

A recipient that understands several members verifies the ones it chooses — "MAY ignore any or all digests" is the RFC's own allowance (`rfc9530.txt:315-317`).

## What compute answers

`Fast::Digest.compute(key, input)` answers exactly the stdlib's bytes for sha-256, sha-512, md5 and sha, as a frozen ASCII-8BIT String (`lib/fast/digest/registry.rb:100-110`):

```ruby
require "digest"
require "fast/digest"

hello = "{\"hello\": \"world\"}"
Fast::Digest.compute("sha-256", hello) == Digest::SHA256.digest(hello)  # => true
```

The four checksum entries (unixsum, unixcksum, adler, crc32c) are registered but deliberately never computed or verified locally: their digest values pass through the fields bytewise, and compute raises `Fast::Digest::Error` naming the key:

```ruby
require "fast/digest"

begin
  Fast::Digest.compute("crc32c", "x")
rescue Fast::Digest::Error => e
  e.message  # => "crc32c is registered but not computable here: construct the field with its explicit digest value"
end
```

An unknown key raises the same way:

```ruby
require "fast/digest"

begin
  Fast::Digest.compute("sha-3", "x")
rescue Fast::Digest::Error => e
  e.message  # => "sha-3 is not in the RFC 9530 hash algorithm registry"
end
```

When you must emit a checksum entry's value, obtain the bytes from the algorithm's own source and construct the field with them explicitly — the RFC 9530 registry is the only source of their digest values.

## Unknown and future algorithms

Unknown keys pass through the fields untouched and answer false/nil on the registry lookups — a future registration never breaks an old gem version (`lib/fast/digest/registry.rb:57-61,63-68`):

```ruby
require "fast/digest"

field = Fast::Digest::ReprDigest.parse("sha-3=:AAAA:")
field["sha-3"].bytesize  # => 3
Fast::Digest.registered?("sha-3")  # => false
```

RFC 9530 §5's registration procedure (Specification Required) is the growth path; the gem pins the table it shipped with (`rfc9530.txt:517-519`). See [The hash algorithm registry](../reference/algorithms.md).
