# Why malformed input answers the defaults

## The RFC recipient contract

§4's design: priority signals ride an extensible Dictionary, so recipients are told what to do with what they cannot read. Four sentences, quoted verbatim: "Receivers parse the Dictionary as described in Section 4.2 of [STRUCTURED-FIELDS]. Where the Dictionary is successfully parsed, this document places the additional requirement that unknown priority parameters, priority parameters with out-of-range values, or values of unexpected types MUST be ignored" (`rfc9218.txt:340-344`); "When receiving an HTTP request that does not carry these priority parameters, a server SHOULD act as if their default values were specified" (`rfc9218.txt:332-334`); "The default is 3" (`rfc9218.txt:350`); "The default value of the incremental parameter is false (0)" (`rfc9218.txt:383`).

Why the RFC chose leniency here (§4.3's extension design: unknown parameters must stay fallback-safe; the registry exists to avoid collisions, `rfc9218.txt:409-458`). New parameters are ignored by old recipients, so extensions cannot break existing scheduling. The registry's two key-length policies keep single-character keys scarce while longer keys stay open.

## Lenient parse, strict everything else

The family principle, stated once: parse as leniently as your RFC demands; emit always strictly. For fast-sfv the RFC demanded strict on both sides (it is the syntax layer); for fast-priority RFC 9218 §4 demands leniency on receipt — the same principle, different RFCs.

`parse` drops §4-ignored members rather than keeping them: an ignored `u=9` re-emitted would be sender garbage — the recipient view and the sender view are different jobs (`lib/fast/priority/field.rb:164-186`).

## Absent is not defaulted

§7: "Omitting a priority parameter is a signal to use its default value" (`rfc9218.txt:523-524`) and §8: "The absence of a priority parameter in an HTTP response indicates the server's disinterest in changing the client-provided value" (`rfc9218.txt:694-696`) — both turn on the difference between absent and defaulted.

Hence the value object's shape: readers answer defaults, `to_s` and `members` show absence (`lib/fast/priority/parameters.rb:70-93`).

## The three failures

The taxonomy (`lib/fast/priority/errors.rb` in full): **TypeError** — a wrong input type is a caller bug, not field content (parse side only, never the emit path); **ParseError** — field content this gem cannot read (the strict view; the lenient parse never raises it, the frame codecs surface it); **SerializeError** — a value that cannot go on the wire (construction and the frame encoders, offset 0, never TypeError).

One `rescue Fast::Priority::Error` guards both field-content failures; caller bugs surface loudly.

## What the defaults buy

Robustness, not laziness: a recipient that defaults on garbage keeps serving; a sender that refuses to emit garbage keeps the wire clean. The RFC's own caution closes the page: "Expressing priority is only a suggestion" (§10, `rfc9218.txt:743-746`).

See [How the priority scheme binds to HTTP/2 and HTTP/3](h2-h3-bindings.md) (where the frames carry the same contract) and [Handle malformed or absent Priority](../how-to-guides/handle-malformed-priority.md).
