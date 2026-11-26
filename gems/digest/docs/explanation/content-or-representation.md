# Content or representation data — the RFC 3230 lesson

## Why two fields exist

RFC 3230's "instance" was read two ways: "Experience has shown that implementations of [RFC3230] have interpreted the meaning of 'instance' inconsistently, leading to interoperability issues. The most common issue relates to the mistake of calculating the digest using (what we now call) message content, rather than using (what we now call) representation data as was originally intended" (`rfc9530.txt:219-226`); Appendix E: "Using content for the Digest field is an error that leads to interoperability problems" and "[RFC3230] was only ever intended to use what HTTP now defines as selected representation data" (`rfc9530.txt:1601-1608`).

RFC 9530's answer: split the question into two named fields — Content-Digest ("applied to the actual message content", `rfc9530.txt:282-285`) and Repr-Digest ("applied to the entire selected representation data", `rfc9530.txt:332-335`) — so "a digest of message content can be beneficial for some use cases" became a first-class field instead of a bug (`rfc9530.txt:226-229`).

## What content is

The bytes the message conveys, whatever Content-Encoding chose (§2 + [HTTP] §6.4; `rfc9530.txt:282-285`); Appendix A's Figure 2: the GZIP-coded upload — the content is the 39 coded bytes, not the 19-byte JSON (`rfc9530.txt:960-976`).

## What selected representation data is

The representation after content coding: what a range request does not deliver in full, what a HEAD response conveys none of, the empty string when no representation data was sent (§3 at `rfc9530.txt:332-348`; the "no representation data" sentence at 345-348); the effect of methods and codings walked in Appendix A (Figures 5/6 the partial response at `rfc9530.txt:1002-1023`, Figures 7/8 the HEAD response at 1027-1042).

## The same bytes, the different fields

B.1: when the message content conveys the complete representation data, both fields carry the same digest — "Content-Digest and Repr-Digest are both computed over the JSON object {"hello": "world"} followed by an LF; thus, they have the same value" (`rfc9530.txt:1091-1094`).

B.2 (HEAD): Content-Digest over empty content (`sha-256=:47DEQpj8HBSa+/TImW+5JCeuQeRkm5NMpJWZG3hSuFU=:`, the digest of the empty string) while Repr-Digest still answers the full representation (`rfc9530.txt:1115-1139`):

```ruby
require "digest"
require "fast/digest"

Digest::SHA256.digest("") ==
  Fast::Digest::ContentDigest.parse("sha-256=:47DEQpj8HBSa+/TImW+5JCeuQeRkm5NMpJWZG3hSuFU=:")["sha-256"]
# => true
```

B.3 (range): Content-Digest over the partial content (`"world"}\n`) while Repr-Digest stays whole (`rfc9530.txt:1141-1164`, the contrast sentences at 1166-1175).

## What the type system enforces

The gem keeps the two apart in the types: `.of` names the input (content vs representation data), and `==` is class-checked on top of the canonical wire form — identical bytes never make a ContentDigest equal a ReprDigest (`lib/fast/digest/fields.rb:318-326,420-422,454-456`):

```ruby
require "fast/digest"

b1 = "sha-256=:RK/0qy18MlBSVnWgjwz6lZEWjP/lF5HF9bvEF8FabDg=:"
Fast::Digest::ContentDigest.parse(b1) == Fast::Digest::ReprDigest.parse(b1)  # => false
```

The class is the answer to "what was hashed" — a value object knows which question it answers; state-changing requests (§3.1) and Content-Location (§3.2) pick the representation side for you in the RFC's own worked cases (B.7/B.8, `rfc9530.txt:393-432,1297-1370`).
