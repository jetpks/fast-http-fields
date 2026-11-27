# fast-http-fields

Five small, standalone Ruby gems. Each one implements a family of HTTP fields exactly as its RFC defines them. They install separately and work together — all five are live on RubyGems.

Parse what is really on the wire, emit the canonical form, frozen value objects, few allocations, pure Ruby — one RFC each, one runtime dependency at most (`fast-sfv`), plus Ruby's own digest library for fast-digest (a default gem, no dependency line).

## The family

| Gem | What it's for | Fields | RFC | Install | Current release |
|-----|---------------|--------|-----|---------|-----------------|
| [`fast-sfv`](gems/sfv/README.md) | the grammar every other gem builds on: parse and emit Structured Field Values | Structured Field Values | RFC 9651 | `gem install fast-sfv` | 0.2.0 |
| [`fast-priority`](gems/priority/README.md) | read and send the Priority field and the HTTP/2/HTTP/3 PRIORITY_UPDATE frame payloads | Priority, PRIORITY_UPDATE | RFC 9218 | `gem install fast-priority` | 0.1.0 |
| [`fast-digest`](gems/digest/README.md) | content and representation digests: check what you received, say what you sent | Content-Digest, Repr-Digest, Want-Content-Digest, Want-Repr-Digest | RFC 9530 | `gem install fast-digest` | 0.1.0 |
| [`fast-proxy-status`](gems/proxy_status/README.md) | the diagnostics family: Proxy-Status, Cache-Status and Targeted Cache Control | Proxy-Status, Cache-Status, CDN-Cache-Control | RFC 9209, RFC 9211, RFC 9213 | `gem install fast-proxy-status` | 0.1.0 |
| [`fast-client-cert`](gems/client_cert/README.md) | the client certificate a proxy forwards to your origin | Client-Cert, Client-Cert-Chain | RFC 9440 | `gem install fast-client-cert` | 0.1.0 |

Five gems, five calls — each gem in one line:

```ruby
require "fast/sfv"
require "fast/priority"
require "fast/digest"
require "fast/proxy_status"
require "fast/client_cert"

Fast::SFV.parse_list("1, 2, 3").map(&:value)  # => [1, 2, 3]
Fast::Priority.parse("u=2, i").urgency        # => 2
Fast::Digest::ContentDigest.of("sha-256", "hello").to_s
# => "sha-256=:LPJNul+wow4m6DsqxbninhsWHlwfp0JecwQzYpOLmCQ=:"
Fast::ProxyStatus.parse("ExampleCDN; error=connection_timeout").first.error
# => #<Fast::SFV::Token "connection_timeout">
Fast::ClientCert::Cert.parse(":aGVsbG8=:").der  # => "hello"
```

The list `1, 2, 3` parsed into three integers. The Priority field says urgency 2 (0 is most urgent, 7 least). The Content-Digest is a checksum — here SHA-256 over `hello` — in the canonical wire form. The Proxy-Status error tells you the intermediary timed out connecting to the origin. The Client-Cert bytes are the raw certificate as TLS carried them (here five bytes; a real one is hundreds). Each of those objects is explained by its gem's own README — linked in the table above.

## Why field-grammar gems

HTTP fields are how the protocol carries meaning — how urgently a client wants an answer, whether a body arrived intact, who the client proved itself to be, what happened on the way. The modern specs define their fields as precise grammars (Structured Field Values), but Ruby code usually meets them as strings and reaches for a regex. Hand-rolled parsing drifts — subtly different workarounds for the same corner cases.

Each gem in this family implements its RFC's grammar exactly — what a recipient may leniently ignore, what a sender must strictly emit — so the drift never starts.

Every gem parses what its RFC tells a recipient to do with input it cannot read — never an exception on the read path. Every gem emits only the canonical wire form (RFC 9651's serialization is the family's emit engine). Results are frozen value objects. Every gem carries allocation budgets as tests (see [why allocation budgets](docs/explanation/why-allocation-budgets.md)). Pure Ruby, no native extensions, no OpenSSL — one runtime dependency at most (`fast-sfv`, the substrate; see [the SFV substrate](docs/explanation/the-sfv-substrate.md)).

The principle behind this is explained in [why lenient-parse, strict-emit](docs/explanation/why-lenient-parse-strict-emit.md).

## Installation

```sh
gem install fast-sfv
gem install fast-priority
gem install fast-digest
gem install fast-proxy-status
gem install fast-client-cert
```

Each gem stands alone — take only the fields you receive. The four field gems pull in `fast-sfv` as their one runtime dependency. In a Gemfile: `gem "fast-digest"` and friends.

Requires Ruby >= 3.4 and RubyGems >= 3.5.3. Require paths: `fast/sfv`, `fast/priority`, `fast/digest`, `fast/proxy_status`, `fast/client_cert`.

## The gems compose

Three gems answering one request:

```ruby
require "fast/priority"
require "fast/digest"
require "fast/proxy_status"

priority = Fast::Priority.parse("u=1, i")                    # the request asks: answer fast
digest   = Fast::Digest::ReprDigest.of("sha-256", "hello")   # the response's integrity
status   = Fast::ProxyStatus.append("tls-proxy", Fast::SFV::Token.new("origin"))

priority.urgency  # => 1
digest.to_s       # => "sha-256=:LPJNul+wow4m6DsqxbninhsWHlwfp0JecwQzYpOLmCQ=:"
status.to_s       # => "tls-proxy, origin"
```

The client asked for urgency 1 — answer soon. The response carries its own digest so the receiver can verify it. The Proxy-Status says which intermediaries handled the response. The gems never know about each other, but the fields they own travel on the same requests and responses — see the [start-here tutorial](docs/tutorials/start-here.md) for the full story, and the two cross-gem how-tos for the composed handler.

## Documentation

The root docs tree — the family's own top-level documentation:

| Path | What it is |
|------|------------|
| **Tutorial** | |
| [`docs/tutorials/start-here.md`](docs/tutorials/start-here.md) | One request, one response, five fields — every gem met once, in one story. |
| **How-to guides** | |
| [`docs/how-to-guides/handle-a-request-with-priority-digest-and-proxy-status.md`](docs/how-to-guides/handle-a-request-with-priority-digest-and-proxy-status.md) | A gateway reading Priority and Content-Digest and Proxy-Status, answering with Proxy-Status extended. |
| [`docs/how-to-guides/validate-a-client-cert-and-report-the-path.md`](docs/how-to-guides/validate-a-client-cert-and-report-the-path.md) | An origin behind a TLS-terminating proxy reading Client-Cert and reporting the outcome with Proxy-Status. |
| **Reference** | |
| [`docs/reference/family-map.md`](docs/reference/family-map.md) | The family map — which gem owns which RFC, the shared substrate, the registries, where every docs tree lives. |
| **Explanation** | |
| [`docs/explanation/why-lenient-parse-strict-emit.md`](docs/explanation/why-lenient-parse-strict-emit.md) | Why every gem parses leniently and emits strictly. |
| [`docs/explanation/why-registries-are-data.md`](docs/explanation/why-registries-are-data.md) | Why the RFC registries are pinned as frozen data, not enforced as rules. |
| [`docs/explanation/why-allocation-budgets.md`](docs/explanation/why-allocation-budgets.md) | Why every gem tests its own allocation budgets — and where the numbers live. |
| [`docs/explanation/the-sfv-substrate.md`](docs/explanation/the-sfv-substrate.md) | What Structured Field Values are and why all five gems share one grammar. |

The root tree explains the family in plain language. Each gem's README is its own front door, linking a full per-gem tree — tutorial, how-to guides, reference, explanations — where the same fields are documented in full technical depth, RFC section by section. The [family map](docs/reference/family-map.md) is the map of that whole layer (54 leaves across the five gems: 10 in fast-sfv, 10 in fast-priority, 11 in fast-digest, 14 in fast-proxy-status, 9 in fast-client-cert).

## The naming rule

Gems are named for the field grammar they implement, not for a vendor or an application. Gem directories are the underscored form (`gems/proxy_status`, `gems/client_cert`) and the require leaf maps `fast/<underscored>`. Gem names and release-tag prefixes are hyphenated (`fast-proxy-status`, `proxy-status-v*`).

## Releases

All five gems are published on RubyGems — fast-sfv at 0.2.0, the other four at 0.1.0. Tags are per gem: `<prefix>-v<semver>` — `sfv-v0.2.0`, `priority-v0.1.0`, `digest-v0.1.0`, `proxy-status-v0.1.0`, `client-cert-v0.1.0`. A bare `v*` tag is rejected by the release workflow — there is no legacy path.

Publishing is RubyGems trusted publishing (OIDC, no API token). The first five releases went out through the workflow's first-publish path and each OWNER entry was dropped after its gem's first release — the map now carries none. Future tags are cut by hand at landing and take the stock keyless credential exchange.

## Development

```sh
bundle install
bundle exec sus        # every gem's suite (config/sus.rb routes gems/*/lib + gems/*/test)
bundle exec rubocop
```

One root bundle (`bundle install`; the root `Gemfile` makes every `gems/*` directory a path gem via its gemspec, glob-driven). One test command runs every gem's suite (`bundle exec sus`; `config/sus.rb` routes every `gems/*/lib` onto the load path and every `gems/*/test` into the run). `bundle exec rubocop` for lint.

CI (`.github/workflows/ci.yml`): spec matrix on Ruby 3.4/4.0, lint, the per-gem build loop (`gem build` from each `gems/*/` directory — nested gemspecs are unbuildable from the repo root), and a security audit. `script/verify-packaged.rb` proves a built package carries its require path from outside the checkout.

MIT license (`LICENSE`; every gemspec carries `spec.license = "MIT"`). Source at `https://github.com/jetpks/fast-http-fields`.
