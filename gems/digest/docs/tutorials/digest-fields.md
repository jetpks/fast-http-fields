# Your first Digest field

You will read and write RFC 9530 Digest Fields with `Fast::Digest` in about ten minutes.

## What you will learn

Parse a digest field and verify it against the stdlib; compute a digest and emit the canonical field; read a preference field; know what a malformed field answers and meet the strict error.

Assumes Ruby >= 3.4 and familiarity with HTTP request/response basics (`fast-digest.gemspec:25`).

## Set up

```sh
gem install fast-digest
```

```ruby
require "fast/digest"
```

## Parse a digest field

The two Integrity fields are Dictionaries of algorithm key => digest Byte Sequence: each key conveys the hashing algorithm, each value "a Byte Sequence … that conveys an encoded version of the byte output produced by the digest calculation" (§2/§3, `rfc9530.txt:289-294,353-357`; `lib/fast/digest.rb:19-25`).

`Fast::Digest::ReprDigest.parse(input)` returns a frozen value object; a String is one field value, an Array is the field's lines (`lib/fast/digest/fields.rb:172-176`).

```ruby
require "fast/digest"

field = Fast::Digest::ReprDigest.parse("sha-256=:RK/0qy18MlBSVnWgjwz6lZEWjP/lF5HF9bvEF8FabDg=:")
field.keys                        # => ["sha-256"]
field["sha-256"].bytesize         # => 32
field["sha-256"].encoding         # => Encoding::ASCII_8BIT
```

A Byte Sequence is a String tagged ASCII-8BIT — the encoding IS the wire-type tag (RFC 9651 §3.3.5 colons-and-base64 form, `rfc9651.txt:650-658`). See [Content or representation data](../explanation/content-or-representation.md) for what was hashed.

## Verify against the standard library

The B.1 value is the digest of the JSON object `{"hello": "world"}` followed by an LF, where "Content-Digest and Repr-Digest are both computed over the JSON object" (B.1, `rfc9530.txt:1089-1113`, the sentence at 1091-1094).

```ruby
require "digest"
require "fast/digest"

body = "{\"hello\": \"world\"}\n"
field = Fast::Digest::ReprDigest.parse("sha-256=:RK/0qy18MlBSVnWgjwz6lZEWjP/lF5HF9bvEF8FabDg=:")
field["sha-256"] == Digest::SHA256.digest(body)  # => true
```

`Fast::Digest.compute` answers exactly those bytes for sha-256, sha-512, md5 and sha — never a reimplementation (`lib/fast/digest/registry.rb:100-110`).

## Compute a digest and emit the field

`Fast::Digest::ReprDigest.of(algorithm, representation_data)` — compute-and-construct:

```ruby
require "digest"
require "fast/digest"

body = "{\"hello\": \"world\"}\n"

repr = Fast::Digest::ReprDigest.of("sha-256", body)
repr.to_s  # => "sha-256=:RK/0qy18MlBSVnWgjwz6lZEWjP/lF5HF9bvEF8FabDg=:"

built = Fast::Digest::ReprDigest.new("sha-256" => Digest::SHA256.digest(body))
built == repr  # => true
```

Construction is strict — a sender never puts garbage on the wire: byte-sequence values must be Strings tagged ASCII-8BIT (a UTF-8 String would emit as a quoted sf-string, so it is refused), keys Structured Fields keys (`lib/fast/digest/fields.rb:258-278`).

`#to_s` answers the canonical RFC 9651 §4.1.2 Dictionary form, `""` when nothing is held — a sender omits the field entirely (`lib/fast/digest/fields.rb:307-316`).

## Read a preference field

The two preference fields are Dictionaries of algorithm key => Integer 0..10: "1 is the least preferred, 10 is the most preferred, and a value of 0 means 'not acceptable'" (§4, `rfc9530.txt:458-466`).

```ruby
require "fast/digest"

want = Fast::Digest::WantReprDigest.parse("sha-512=3, sha-256=10, unixsum=0")
want.keys      # => ["sha-512", "sha-256", "unixsum"]
want["sha-256"]  # => 10
want.to_s      # => "sha-512=3, sha-256=10, unixsum=0"
```

Preferences are a hint — the selection policy is the caller's, and the preference classes carry no compute helper (`lib/fast/digest/fields.rb:459-465`). See [Ask for digests with Want-Content-Digest and Want-Repr-Digest](../how-to-guides/request-digest-preferences.md).

## When the field is wrong

`parse` never raises on field content: malformed input answers the EMPTY value object — the same answer an absent field gives:

```ruby
require "fast/digest"

Fast::Digest::ReprDigest.parse("!!").empty?  # => true
Fast::Digest::ReprDigest.parse("!!").to_s    # => ""
Fast::Digest::ReprDigest.parse("md5=5").empty?  # => true
```

`parse!` is the strict view: it raises `Fast::Digest::ParseError` with `#offset`, the byte position of the offending member's VALUE in the combined field value:

```ruby
require "fast/digest"

begin
  Fast::Digest::ReprDigest.parse!("md5=5")
rescue Fast::Digest::ParseError => e
  e.offset  # => 4
end
```

When you only need a yes/no: `Fast::Digest::ReprDigest.valid?("md5=5")  # => false` (`lib/fast/digest/fields.rb:200-205`). See [What digests do and do not protect](../explanation/security-posture.md) for why the gem refuses to guess.

## Where next

- [Validate an upload's Content-Digest in Rack](../how-to-guides/validate-an-upload-content-digest.md)
- [Emit digests while streaming](../how-to-guides/emit-digests-while-streaming.md)
- [Ask for digests with Want-Content-Digest and Want-Repr-Digest](../how-to-guides/request-digest-preferences.md)
- [Choose hashing algorithms](../how-to-guides/choose-algorithms.md)
- [API reference](../reference/api.md)
- [The hash algorithm registry](../reference/algorithms.md)
