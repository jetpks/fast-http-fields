# How the priority scheme binds to HTTP/2 and HTTP/3

## Why a new scheme

RFC 7540 stream priority: a dependency tree, limited deployment and interoperability, servers that do not act on it; the replacement is "simpler and more constrained, requiring less interpretation and allowing less variation" (§2, `rfc9218.txt:180-210`, the quote at 202) — and RFC 7540 priority could not express a server's signal for intermediaries (`rfc9218.txt:205-206`).

Independent-research note (§2, `rfc9218.txt:211-214`): simpler schemes reached at least equivalent performance for the Web use case.

## The SETTINGS_NO_RFC7540_PRIORITIES story

The setting's purpose: let endpoints omit or ignore RFC 7540 priority signals (§2.1, `rfc9218.txt:220-232`); the HTTP/2 settings code is 0x9 (the IANA registration, `rfc9218.txt:989-991`).

The rules, quoted: "If endpoints use SETTINGS_NO_RFC7540_PRIORITIES, they MUST send it in the first SETTINGS frame. Senders MUST NOT change the SETTINGS_NO_RFC7540_PRIORITIES value after the first SETTINGS frame" (`rfc9218.txt:234-236`); the value MUST be 0 or 1, anything else is a connection error of type PROTOCOL_ERROR (`rfc9218.txt:228-231`); client value 1 = the client ignores HTTP/2 priority signals (and a receiving server MUST ignore them), server value 1 = the server will ignore client signals (`rfc9218.txt:240-250`).

§2.1.1's advice, one paragraph: until the first SETTINGS frame arrives, a client SHOULD send both the HTTP/2 priority signals and this scheme's; once the parameter reads 1, stop the HTTP/2 signals; once it reads 0 or absent, stop the PRIORITY_UPDATE frames (the Priority header field may continue — it is end-to-end) (`rfc9218.txt:257-277`).

A SETTINGS frame belongs to the connection, so this is documentation here, never behavior (`lib/fast/priority/h2.rb:23-29`).

## End-to-end field, hop-by-hop frames

The Priority header field is "an end-to-end signal that indicates the endpoint's view of how HTTP responses should be prioritized" (§5, `rfc9218.txt:474-483`, the quote at 478); the PRIORITY_UPDATE frame is a hop-by-hop signal sent on the control stream (§7, `rfc9218.txt:511-517`).

The intermediary's three choices, one paragraph each with §4's own words: pass the Priority header field unchanged (preserve the end-to-end signal), add a PRIORITY_UPDATE frame (preserve the client's signal, instruct the next hop differently), or replace the Priority header field (override the client's signal) (`rfc9218.txt:311-324`).

## The frame, minus the transport

What the gem owns: the payload bytes — the identifier word/varint plus the field value — and the §4 parse of the value (`lib/fast/priority.rb:46-53`).

What the transport owns, one bullet each with § citations: the HTTP/2 frame header and the header Stream Identifier MUST-be-zero (§7.1 at `rfc9218.txt:555-557`); the HTTP/2 stream-state expectations for request and push streams (§7.1 at 589-611); "Servers MUST NOT send PRIORITY_UPDATE frames" (§7.1 at 613); the HTTP/3 placement rule, quoted: "The PRIORITY_UPDATE frame MUST be sent on the client control stream" (§7.2 at `rfc9218.txt:628` — receiving it on another stream is a connection error of type H3_FRAME_UNEXPECTED); the request/push reference rules and H3_ID_ERROR (§7.2 at 649-668); the buffer-the-latest-frame advice for the early-frame race (§7 at 527-545).

## The HTTP/3 reality

The QUIC varint (RFC 9000 §16) and the no-ordering-guarantees context (§7 at `rfc9218.txt:517-519`).

No usable Ruby HTTP/3 framing stack exists today (the published protocol-http3 releases are native extensions without a frame API); this gem's HTTP/3 codec is vector-verified against the RFCs while the HTTP/2 codec carries the real protocol-http2 interop — the same boundary either way: payloads, not connection state.
