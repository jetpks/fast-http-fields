# Emit Priority from a server

## Build the value

`Fast::Priority::Parameters.new(urgency:, incremental:, unknown:)`, all keywords optional; construction validates (SerializeError for an out-of-range urgency, a non-Boolean incremental, or a bad unknown member) (`lib/fast/priority/parameters.rb:57-68,169-213`).

```ruby
require "fast/priority"

priority = Fast::Priority::Parameters.new(urgency: 1)
priority.to_s  # => "u=1"

Fast::Priority::Parameters.new(urgency: 6, incremental: false).to_s  # => "u=6, i=?0"
```

An omitted member is absent on the wire (not defaulted) — §8, quoted: "The absence of a priority parameter in an HTTP response indicates the server's disinterest in changing the client-provided value" (`rfc9218.txt:694-696`); `to_s` omits absent members (`lib/fast/priority/parameters.rb:89-93`).

## Emit it

`#to_s` — the canonical RFC 9651 §4.1.2 form, `""` for no members: omit the header entirely then (a sender never puts an empty field on the wire) (`lib/fast/priority/parameters.rb:89-93`).

The emit path is always strict — senders never produce garbage; the wrong-typed input raises SerializeError, never TypeError (`lib/fast/priority/errors.rb:28-44`).

## Merge client and server signals

§8 verbatim: "No guidance is provided for merging priorities; this is left as an implementation decision" (`rfc9218.txt:690-692`). `Parameters#merge` implements the RFC's own worked example's rule (the u=5,i request met by a u=1 response at `rfc9218.txt:698-716`): every parameter the other holds wins, its omissions keep self's, the unknown members union with the other's winning collisions — a new frozen object, both inputs untouched (`lib/fast/priority/parameters.rb:102-107`).

```ruby
require "fast/priority"

client = Fast::Priority.parse("u=5, i")
server = Fast::Priority.parse("u=1")
merged = client.merge(server)
merged.urgency      # => 1
merged.incremental  # => true
merged.to_s         # => "u=1, i"
```

A caller with a different policy writes their own merge over `#members` (the values are frozen Hash entries of SFV Items/InnerLists).

## Set the response header

In Rack terms: the response headers Hash:

```ruby
require "fast/priority"

priority = Fast::Priority.parse("u=1")
headers = { "priority" => priority.to_s }
headers["priority"]  # => "u=1"
```

The Priority response header is advice to intermediaries, not an acknowledgement that prioritization occurred (§5, `rfc9218.txt:480-483`).
