# What digests do and do not protect

## Not a message-level protection

"This document specifies a data integrity mechanism that protects HTTP representation data or content, but not HTTP header and trailer fields, from certain kinds of corruption" and "Integrity fields are not intended to be a general protection against malicious tampering with HTTP messages. In the absence of additional security mechanisms, an on-path malicious actor can either remove a digest value entirely or substitute it with a new digest value computed over manipulated representation data or content. This attack can be mitigated by combining mechanisms described in this document with other approaches such as Transport Layer Security (TLS) or digital signatures" (`rfc9530.txt:559-573`).

The fail-closed parse is the gem's share of the posture: what cannot be read is treated as absent, never guessed (`rfc9651.txt:279-288`); "This specification does not define means for authentication, authorization, or privacy" (`rfc9530.txt:208-210`).

## End-to-end integrity for data, not metadata

Digests "can help detect representation data or content modification due to implementation errors, undesired 'transforming proxies', or other actions as the data passes across multiple hops or system boundaries" — but "using these mechanisms alone does not provide end-to-end integrity of HTTP messages over multiple hops since metadata could be manipulated at any stage" (`rfc9530.txt:575-589`).

## Signatures

"Digests explicitly depend on the 'representation metadata' (e.g., the values of Content-Type, Content-Encoding, etc.). A signature that protects Integrity fields but not other 'representation metadata' can expose the communication to tampering" (`rfc9530.txt:604-608`); the empty-string digest signed makes added content detectable (`rfc9530.txt:610-616`); "Any mangling of Integrity fields might affect signature validation. Examples of such mangling include de-duplicating digests or combining different field values" (`rfc9530.txt:621-625`) — the caution behind the Array-combining contract.

§6.5's content-coding note: variations within a content coding mean a digest is not a proof of integrity "at rest" unless the whole content is persisted (`rfc9530.txt:647-660`).

## Trailers

Intermediaries "are explicitly allowed to drop any trailer"; "Eager processing of content before the trailer section prevents digest validation" — and the benefit that stays true: hashing bytes as they are sent (`rfc9530.txt:627-645`). See [Emit digests while streaming](../how-to-guides/emit-digests-while-streaming.md).

## Resource exhaustion

Validation consumes resources; implementations "can restrict validation of the algorithm types, the number of validations, or the size of content" — and skipping validation of a more-preferred algorithm "leaves the possibility of a downgrade attack" (`rfc9530.txt:688-695`). The gem's boundary: it parses and compares bytes; how much you validate and how you act on failure are caller policy (§2/§3's MAY-ignore, `rfc9530.txt:315-317`).
