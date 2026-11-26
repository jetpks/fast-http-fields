# fast-digest

fast-digest is the RFC 9530 Digest Fields implementation for Ruby: Content-Digest, Repr-Digest, Want-Content-Digest and Want-Repr-Digest, built on fast-sfv.

## What it is

Implements RFC 9530: the two Integrity fields (§2, §3) as RFC 9651 Dictionaries of algorithm key => digest Byte Sequence — `Fast::Digest::ContentDigest` and `Fast::Digest::ReprDigest` — and the two preference fields (§4) as Dictionaries of algorithm key => Integer 0..10 — `Fast::Digest::WantContentDigest` and `Fast::Digest::WantReprDigest`.

The hash-algorithm registry of §7.2 Table 2 is pinned as frozen data (`Fast::Digest::ALGORITHMS`), unknown keys passing through. `Fast::Digest.compute` answers exactly the stdlib's bytes for sha-256, sha-512, md5 and sha.

The lenient parse (`parse`) answers a recipient's view and never raises on field content; the strict parse (`parse!`) tells the truth with byte offsets; `to_s` and construction are always strict. Results are frozen value objects; one runtime dependency (fast-sfv) plus the stdlib digest library.

Pure Ruby, no OpenSSL, no zlib. MIT license. Source at `https://github.com/jetpks/fast-http-fields`.

## Status

In development. The documentation pass arrives with the docs iteration, and the 0.1.0 release follows it — docs are part of the product. The four-field surface, the registry and the compute helpers here are complete and covered by the suite; this README is the front door, not the documentation tree.

## Installation

Not yet published. Until the first release, use the monorepo checkout:

```sh
gem "fast-digest", path: "gems/digest"   # from a fast-http-fields checkout
gem "fast-sfv"                           # the substrate, published as 0.1.1
```

Require path is `fast/digest`:

```ruby
require "fast/digest"
```

Requires Ruby >= 3.4 and RubyGems >= 3.5.3. The only runtime requirement is fast-sfv (the stdlib digest library is a default gem, no dependency line).

## Quickstart

Parse a Content-Digest and verify it against the stdlib — the day-one idiom works bytewise:

```ruby
require "fast/digest"

body = "{\"hello\": \"world\"}\n"
field = Fast::Digest::ContentDigest.parse("sha-256=:RK/0qy18MlBSVnWgjwz6lZEWjP/lF5HF9bvEF8FabDg=:")

field["sha-256"] == Digest::SHA256.digest(body)   # => true
field.keys                                       # => ["sha-256"]
field.to_s                                       # => "sha-256=:RK/0qy18…bDg=:"
```

Compute a digest and emit the field — one line each direction:

```ruby
repr = Fast::Digest::ReprDigest.of("sha-256", body)
repr.to_s == "sha-256=:RK/0qy18MlBSVnWgjwz6lZEWjP/lF5HF9bvEF8FabDg=:"   # => true

content = Fast::Digest::ContentDigest.new("sha-256" => Digest::SHA256.digest(body))
content.to_s   # => "sha-256=:RK/0qy18…bDg=:"
```

Read a preference field, the §4 example:

```ruby
want = Fast::Digest::WantReprDigest.parse("sha-512=3, sha-256=10, unixsum=0")
want["sha-256"]   # => 10
want["unixsum"]   # => 0
want.to_s         # => "sha-512=3, sha-256=10, unixsum=0"
```

## Content or representation data — the class is the answer

RFC 9530 exists because RFC 3230's "instance" was read two ways (§1.3: implementations mistook it for message content; Appendix E: "Using content for the Digest field is an error that leads to interoperability problems"). The two Integrity fields split the question in two, and the gem keeps them apart in the type system:

- `ContentDigest` (§2) — "a hashing algorithm applied to the actual message content": the bytes the message conveys, what Content-Encoding chose.
- `ReprDigest` (§3) — "applied to the entire selected representation data": what a range request does not deliver, the empty string when no representation data was sent (§3, §6.3).

`ContentDigest.of` hashes content, `ReprDigest.of` hashes representation data, and a ContentDigest never equals a ReprDigest whatever their bytes — `==` is class-checked on top of the canonical wire form.

## The fail-closed parse

`parse` is the recipient's view and never raises on field content: a malformed field, or a field whose Dictionary carries ANY member violating the field's constraint (an Integrity member that is not a Byte Sequence, a preference member that is not an Integer 0..10), is the entire field ignored (RFC 9651 §2.2 — RFC 9530 defines no other handling), answering the empty value object — the same answer an absent field gives. No member-level filtering: a valid member beside a bad one drops with the field. "A recipient MAY ignore any or all digests" is caller policy, never the parse's.

`parse!` is the strict truth: the Dictionary failure wrapped with its message and byte offset, the first constraint offender raised at that member's VALUE offset in the combined field value. `valid?` mirrors it with a boolean.

## The registry as data

`Fast::Digest::ALGORITHMS` carries Table 2's eight entries in order with their statuses — sha-512 and sha-256 Active, md5, sha, unixsum, unixcksum, adler and crc32c Deprecated — and `Fast::Digest.registered?`/`status`/`active?`/`deprecated?`/`computable?` answer with unknown keys passing through: a future registration never breaks an old gem version. The status is advisory (§5: a Deprecated algorithm "MAY be used to preserve integrity against corruption, but MUST NOT be used in a potentially adversarial setting") — md5 and sha parse, emit and compute exactly like the Active ones.

`Fast::Digest.compute` answers the stdlib's exact bytes for the four computable algorithms. The four checksum entries — unixsum, unixcksum, adler, crc32c — are registered but carry no local implementation and are deliberately never computed or verified here: their field values pass through bytewise, and `compute` raises `Fast::Digest::Error` naming the key (an unknown key raises the same way).

## Trailer fields and combining

All four fields can arrive as trailers (§2/§3: "MAY be merged into the header section"), and an HTTP message can carry the same field on several lines — the entry points accept an Array of field lines, combined with ", " per RFC 9651 §4.2, duplicates last-wins:

```ruby
field = Fast::Digest::ContentDigest.parse(["sha-256=:AAAA:", "md5=:BBBB:"])
field.keys   # => ["sha-256", "md5"]
```

Read §6.4 and §6.3 before trusting a trailer: intermediaries are allowed to drop trailers, and eager processing of content before the trailer arrives prevents digest validation. And when a signature covers the field, "de-duplicating digests or combining different field values" mangles what it covers — the combining here is the parse contract; what a signature sees is the caller's context.

## The error hierarchy

`Fast::Digest::Error` → `ParseError`/`SerializeError`, both carrying `#offset` — the family shape. The base `Error` is raised in its own right by `compute` and the `.of` helpers: a usage failure, neither a parse nor a serialization defect.
