# The hash algorithm registry

## The registry as data

§7.2 created the "Hash Algorithms for HTTP Digest Fields" registry and populated it with Table 2's eight entries (`rfc9530.txt:719-773`, Table 2 at 773); §5 sets the growth policy (Specification Required, `rfc9530.txt:517-519`).

The gem pins the table at publication as frozen data, unknown keys passing through — a future registration never breaks an old gem version (`lib/fast/digest/registry.rb:12-24`).

## Table 2

The eight-entry table rendered from `ALGORITHMS` verbatim — key, status, description — in the registry's order:

| key | status | description |
|---|---|---|
| sha-512 | Active | The SHA-512 algorithm. |
| sha-256 | Active | The SHA-256 algorithm. |
| md5 | Deprecated | The MD5 algorithm. It is vulnerable to collision attacks; see [NO-MD5] and [CMU-836068] |
| sha | Deprecated | The SHA-1 algorithm. It is vulnerable to collision attacks; see [NO-SHA] and [IACR-2020-014] |
| unixsum | Deprecated | The algorithm used by the UNIX "sum" command. |
| unixcksum | Deprecated | The algorithm used by the UNIX "cksum" command. |
| adler | Deprecated | The ADLER32 algorithm. |
| crc32c | Deprecated | The CRC32c algorithm. |

The descriptions are Table 2's own text, its bracket citation keys pointing into RFC 9530 §8's reference list (`lib/fast/digest/registry.rb:24-44`).

## The lookups

| method | signature | returns | unknown key | example |
|---|---|---|---|---|
| `registered?` | `(key) → Boolean` | true/false | false | `Fast::Digest.registered?("crc32c")  # => true` |
| `status` | `(key) → String\|nil` | "Active" / "Deprecated" / nil | nil | `Fast::Digest.status("sha-256")  # => "Active"` |
| `active?` | `(key) → Boolean` | true/false | false | `Fast::Digest.active?("md5")  # => false` |
| `deprecated?` | `(key) → Boolean` | true/false | false | `Fast::Digest.deprecated?("md5")  # => true` |
| `computable?` | `(key) → Boolean` | true for sha-256, sha-512, md5, sha | false | `Fast::Digest.computable?("crc32c")  # => false` |

Active algorithms "are suitable for many purposes and it is RECOMMENDED that applications use these algorithms. These can be used in adversarial situations where hash functions might need to provide resistance to collision, first-preimage, and second-preimage attacks" (`rfc9530.txt:491-495`). Deprecated algorithms "MAY be used to preserve integrity against corruption, but MUST NOT be used in a potentially adversarial setting" (`rfc9530.txt:502-505`) (`lib/fast/digest/registry.rb:57-89`).

## Computability

`COMPUTABLE` is the four stdlib algorithms (sha-256, sha-512, md5, sha); the four checksum entries are registered but carry no local implementation — their field values pass through bytewise, `compute` refuses them naming the key (`lib/fast/digest/registry.rb:46-52,112-119`). `computable?` answers false for them and for unknown keys.

The split is deliberate — no cryptographic verification of the checksum entries locally, the registry is the only source of their digest values. See [Algorithm agility and the registry's statuses](../explanation/algorithm-agility.md).

## Unknown keys and future registrations

Unknown keys pass through the fields untouched and answer false/nil on the registry lookups — a future registration never breaks an old gem version:

```ruby
require "fast/digest"

field = Fast::Digest::ReprDigest.parse("sha-3=:AAAA:")
field["sha-3"].bytesize  # => 3
Fast::Digest.registered?("sha-3")  # => false
```

RFC 9530 §5's registration procedure (Specification Required) is the growth path; the gem pins the table it shipped with (`rfc9530.txt:517-519`).

## How the registry is pinned

`test/fast/digest/registry.rb` freezes Table 2's eight keys in order, the Active/Deprecated statuses, a description per frozen entry, the lookups' unknown answers, and compute's stdlib ground truth (112 lines). The registry is data the tests freeze, not behavior the gem enforces.
