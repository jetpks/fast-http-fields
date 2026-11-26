# Ask for digests with Want-Content-Digest and Want-Repr-Digest

Build and emit Want-Content-Digest / Want-Repr-Digest, read a peer's preferences, and run your own selection policy.

## What the preference fields say

§4: the Dictionary of algorithm key => Integer 0..10, "1 is the least preferred, 10 is the most preferred, and a value of 0 means 'not acceptable'" (`rfc9530.txt:464-466`); Want-Content-Digest solicits a Content-Digest, Want-Repr-Digest a Repr-Digest (`rfc9530.txt:440-445`).

```ruby
require "fast/digest"

want = Fast::Digest::WantReprDigest.new("sha-256" => 10, "md5" => 0)
want.to_s  # => "sha-256=10, md5=0"
```

Construction is strict as everywhere: an Integer 0..10 per member or SerializeError (`lib/fast/digest/fields.rb:258-278`).

## Read a peer's preferences

C.1's own request:

```ruby
require "fast/digest"

want = Fast::Digest::WantReprDigest.parse("sha-256=3, sha=10")
want["sha"]  # => 10
want.keys    # => ["sha-256", "sha"]
```

The C.1 story: the client prefers "sha" — "The server is free to reply with 'sha-256' anyway" (`rfc9530.txt:1492-1493`); C.2's server "is not obliged to produce a response containing a 'sha' digest" and picks sha-512 instead (`rfc9530.txt:1514-1516`). A Want field used in a RESPONSE asks the client to send the Integrity field on future requests (`rfc9530.txt:447-449`).

## Run your own selection

The gem carries no selection helper — deliberately: "Integrity preference fields are only a hint … It is not a protocol error if preferences are ignored" (`rfc9530.txt:451-456`; `lib/fast/digest/fields.rb:459-465`). The policy is the caller's; a highest-preference computable selection:

```ruby
require "fast/digest"

want = Fast::Digest::WantReprDigest.parse("sha-256=3, sha=10, md5=5")
computable = want.keys.select { |key| Fast::Digest.computable?(key) }
computable  # => ["sha-256", "sha", "md5"]
computable.max_by { |key| want[key] }  # => "sha"
```

"A receiver that depends on a digest for security will be vulnerable to attacks on the weakest algorithm it is willing to accept" (`rfc9530.txt:674-676`) — selection is a security decision, not a sort. See [Algorithm agility and the registry's statuses](../explanation/algorithm-agility.md) and [Choose hashing algorithms](choose-algorithms.md).

## What the answer looks like

The reply you asked for is an Integrity field — parse it with the Repr-Digest/Content-Digest entry points and verify as the [content validation guide](validate-an-upload-content-digest.md) does; the preference classes parse, emit and compare like every field class (see the [tutorial](../tutorials/digest-fields.md) and [API reference](../reference/api.md)).
