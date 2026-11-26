# fast-digest

fast-digest is the RFC 9530 Digest Fields implementation for Ruby: Content-Digest, Repr-Digest, Want-Content-Digest and Want-Repr-Digest, built on fast-sfv.

## What it is

Implements RFC 9530's four fields as RFC 9651 Dictionaries: the two Integrity fields — `Fast::Digest::ContentDigest` (§2, "a hashing algorithm applied to the actual message content") and `Fast::Digest::ReprDigest` (§3, "applied to the entire selected representation data") — as algorithm key => digest Byte Sequence, and the two preference fields — `WantContentDigest` and `WantReprDigest` (§4) — as algorithm key => Integer 0..10 (`lib/fast/digest.rb:19-30`; `rfc9530.txt:282-294,332-357,458-466`).

The hash-algorithm registry of §7.2 Table 2 pinned as frozen data (`Fast::Digest::ALGORITHMS`), unknown keys passing through; `Fast::Digest.compute` answers exactly the stdlib's bytes for sha-256, sha-512, md5 and sha (`lib/fast/digest/registry.rb:24-52,100-110`).

The lenient parse (`parse`) answers a recipient's view and never raises on field content; the strict parse (`parse!`) tells the truth with byte offsets; `to_s` and construction are always strict; results are frozen value objects; one runtime dependency (fast-sfv) plus the stdlib digest library (`lib/fast/digest.rb:32-58`; `fast-digest.gemspec:50`).

Pure Ruby, no OpenSSL, no zlib; the class names carry the content-versus-representation distinction (`lib/fast/digest.rb:26-30,71-73`).

MIT license; source at `https://github.com/jetpks/fast-http-fields` (`fast-digest.gemspec:21-23`).

## Installation

```sh
gem install fast-digest
```

In a Gemfile:

```ruby
gem "fast-digest"
```

Require path is `fast/digest`:

```ruby
require "fast/digest"
```

Requires Ruby >= 3.4 and RubyGems >= 3.5.3; the only runtime requirement is fast-sfv — the stdlib digest library is a default gem, no dependency line (`fast-digest.gemspec:25-26,47-50`).

## Quickstart

The day-one byte-sequence comparison:

```ruby
require "fast/digest"

body = "{\"hello\": \"world\"}\n"
field = Fast::Digest::ContentDigest.parse("sha-256=:RK/0qy18MlBSVnWgjwz6lZEWjP/lF5HF9bvEF8FabDg=:")

field["sha-256"] == Digest::SHA256.digest(body)   # => true
```

`[]` answers the bare digest bytes as a frozen ASCII-8BIT String, so the bytewise comparison with the stdlib holds on day one (`lib/fast/digest/fields.rb:283-285`; `lib/fast/digest.rb:51-53`).

Compute and emit, one line each direction:

```ruby
repr = Fast::Digest::ReprDigest.of("sha-256", body)
repr.to_s  # => "sha-256=:RK/0qy18MlBSVnWgjwz6lZEWjP/lF5HF9bvEF8FabDg=:"

content = Fast::Digest::ContentDigest.new("sha-256" => Digest::SHA256.digest(body))
content.to_s  # => "sha-256=:RK/0qy18MlBSVnWgjwz6lZEWjP/lF5HF9bvEF8FabDg=:"
```

The preference field, §4's own example:

```ruby
want = Fast::Digest::WantReprDigest.parse("sha-512=3, sha-256=10, unixsum=0")
want["sha-256"]  # => 10
want["unixsum"]  # => 0
want.to_s        # => "sha-512=3, sha-256=10, unixsum=0"
```

Next: the [tutorial](docs/tutorials/digest-fields.md) for the guided path.

## Content or representation data — the class is the answer

RFC 9530 exists because RFC 3230's "instance" was read two ways (§1.3; `rfc9530.txt:219-226`; Appendix E: "Using content for the Digest field is an error that leads to interoperability problems" at `rfc9530.txt:1601-1604`).

- `ContentDigest` (§2) — content: the bytes the message conveys, what Content-Encoding chose.
- `ReprDigest` (§3) — selected representation data: what a range request does not deliver, the empty string when no representation data was sent (`rfc9530.txt:345-348`).

`ContentDigest.of` hashes content, `ReprDigest.of` hashes representation data, and a ContentDigest never equals a ReprDigest whatever their bytes — `==` is class-checked on top of the canonical wire form (`lib/fast/digest/fields.rb:318-326,420-422,454-456`). See [Content or representation data](docs/explanation/content-or-representation.md).

## The fail-closed parse

`parse` never raises on field content: a malformed field, or a field whose Dictionary carries ANY member violating the field's constraint (an Integrity member that is not a Byte Sequence, a preference member that is not an Integer 0..10), is the entire field ignored (RFC 9651 §2.2 — "When field-specific constraints are violated, the entire field is also ignored, unless the field definition defines other handling requirements", RFC 9530 defines none), answering the empty value object — the same answer an absent field gives. No member-level filtering: a valid member beside a bad one drops with the field (`rfc9651.txt:279-288`; `lib/fast/digest/fields.rb:158-176`).

"A recipient MAY ignore any or all digests" (§2/§3, `rfc9530.txt:315-317,379-381`) is caller policy, never the parse's.

`parse!` is the strict truth: the Dictionary failure wrapped with its message and byte offset, the first constraint offender raised at that member's VALUE offset in the combined field value; `valid?` mirrors it with a boolean (`lib/fast/digest/fields.rb:188-205`). See [Validate an upload's Content-Digest in Rack](docs/how-to-guides/validate-an-upload-content-digest.md).

## The registry as data

`Fast::Digest::ALGORITHMS` carries Table 2's eight entries in order with their statuses — sha-512 and sha-256 Active, md5, sha, unixsum, unixcksum, adler and crc32c Deprecated — and `registered?`/`status`/`active?`/`deprecated?`/`computable?` answer with unknown keys passing through: a future registration never breaks an old gem version (`lib/fast/digest/registry.rb:24-52,59-89`). The status is advisory (§5: a Deprecated algorithm "MAY be used to preserve integrity against corruption, but MUST NOT be used in a potentially adversarial setting", `rfc9530.txt:502-504`) — md5 and sha parse, emit and compute exactly like the Active ones.

`Fast::Digest.compute` answers the stdlib's exact bytes for the four computable algorithms; the four checksum entries are registered but never computed or verified here — their field values pass through bytewise, and `compute` raises `Fast::Digest::Error` naming the key (`lib/fast/digest/registry.rb:46-52,100-110`). See [The hash algorithm registry](docs/reference/algorithms.md) and [Algorithm agility and the registry's statuses](docs/explanation/algorithm-agility.md).

## Trailer fields and combining

All four fields can arrive as trailers (§2/§3: "MAY be merged into the header section", `rfc9530.txt:326-328,386-392`), and an HTTP message can carry the same field on several lines — the entry points accept an Array of field lines, combined with ", " per RFC 9651 §4.2 ("parsers MUST combine all field lines in the field name into one comma-separated field-value", `rfc9651.txt:1154-1156`), duplicates last-wins (`lib/fast/digest/fields.rb:209-214,269-278`):

```ruby
field = Fast::Digest::ContentDigest.parse(["sha-256=:AAAA:", "md5=:BBBB:"])
field.keys  # => ["sha-256", "md5"]
```

Read §6.4 and §6.3 before trusting a trailer — intermediaries are allowed to drop trailers, eager processing of content before the trailer arrives prevents digest validation, and a signature that covers the field sees what the combining produced (`rfc9530.txt:627-645,621-625`). See [Emit digests while streaming](docs/how-to-guides/emit-digests-while-streaming.md) and [What digests do and do not protect](docs/explanation/security-posture.md).

## The error hierarchy

`Fast::Digest::Error` → `ParseError`/`SerializeError`, both carrying `#offset` — the family shape. The base `Error` is raised in its own right by `compute` and the `.of` helpers: a usage failure, neither a parse nor a serialization defect (`lib/fast/digest/errors.rb:5-16,28-35,47-54`). See [API reference](docs/reference/api.md).

## Documentation

Current release 0.1.0; changelog at [CHANGELOG.md](CHANGELOG.md).

### Tutorial

- [Your first Digest field](docs/tutorials/digest-fields.md) — One guided path: parse a Repr-Digest and verify it against the stdlib, compute and emit one, read a preference field, and meet the fail-closed empty value and the strict error.

### How-to guides

- [Validate an upload's Content-Digest in Rack](docs/how-to-guides/validate-an-upload-content-digest.md) — Read an upload's Content-Digest in a Rack-shaped env, parse it, compare against the received bytes, and handle absence, malformed input, and multiple lines.
- [Emit digests while streaming](docs/how-to-guides/emit-digests-while-streaming.md) — Hash content as it streams with the stdlib, build the field, send it as a header or a trailer, and know the trailer cautions.
- [Ask for digests with Want-Content-Digest and Want-Repr-Digest](docs/how-to-guides/request-digest-preferences.md) — Build and emit Want-Content-Digest / Want-Repr-Digest, read a peer's preferences, and run your own selection policy.
- [Choose hashing algorithms](docs/how-to-guides/choose-algorithms.md) — Choose algorithms with the registry lookups, emit multi-algorithm fields for transitions, and know what compute answers and refuses.

### Reference

- [API reference](docs/reference/api.md) — The complete surface: the four field classes, the parsing entry points, the value object, construction, the registry functions, and the errors.
- [The hash algorithm registry](docs/reference/algorithms.md) — The hash-algorithm registry: RFC 9530 §7.2 Table 2 as data, the lookups, computability, unknown-key passthrough, and how the registry is pinned.

### Explanation

- [Content or representation data — the RFC 3230 lesson](docs/explanation/content-or-representation.md) — Why content and selected representation are different digest inputs — the RFC 3230 lesson, the Appendix A/B worked examples, and what the type system enforces.
- [Algorithm agility and the registry's statuses](docs/explanation/algorithm-agility.md) — Why agility is designed in, what Active and Deprecated mean (and do not), the weakest-algorithm rule, and why the registry is pinned data.
- [What digests do and do not protect](docs/explanation/security-posture.md) — What digests do and do not protect: the on-path substitution attack, end-to-end integrity for data but not metadata, signatures, and trailers.
- [Performance and allocation budgets](docs/explanation/performance.md) — How the paths stay allocation-lean; the both-mode benchmark tables and the allocation budgets, with methodology and caveats.
