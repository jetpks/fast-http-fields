# fast-http-fields

The fast-http-fields monorepo: a collection of small, standalone,
releasable Ruby gems, each implementing one HTTP field grammar
faithfully to its RFC. Pure Ruby throughout; the only runtime
dependency anywhere in the family is `fast-sfv` itself — the substrate
the other four fields are built on (every one of them is a Structured
Field Value).

## What lives here

| Gem | RFCs | Status |
|-----|------|--------|
| [`gems/sfv`](gems/sfv/README.md) — `fast-sfv` (`Fast::SFV`) | RFC 9651 (8941 is the documented subset) | 0.1.0 |
| [`gems/priority`](gems/priority/README.md) — `fast-priority` (`Fast::Priority`) | RFC 9218 | implemented |
| [`gems/digest`](gems/digest/README.md) — `fast-digest` (`Fast::Digest`) | RFC 9530 | implemented |
| [`gems/proxy_status`](gems/proxy_status/README.md) — `fast-proxy-status` (`Fast::ProxyStatus`, `Fast::CacheStatus`, `Fast::TargetedCacheControl`) | RFC 9209, 9211, 9213 | in progress |
| [`gems/client_cert`](gems/client_cert/README.md) — `fast-client-cert` (`Fast::ClientCert`) | RFC 9440 | in progress |

The remaining gems are built in dependency order
(fast-sfv first — it must be published before the dependents can
package). The machinery (CI, release dispatch map, packaging verify,
test harness) covers all five from day one; a new gem directory needs
no machinery edit.

## The naming rule

Gems are named for the field grammar they implement, not for a vendor
or an application: `fast-sfv` implements Structured Field Values,
`fast-proxy-status` implements the Proxy-Status field. Gem
directories are the underscored form (`gems/proxy_status`,
`gems/client_cert`) and the require leaf maps `fast/<underscored>`
(`require "fast/proxy_status"`); gem names and release-tag prefixes
are hyphenated (`fast-proxy-status`, `proxy-status-v*`).

## Releases

Tags are per gem: `<prefix>-v<semver>` — `sfv-v0.1.0`,
`priority-v0.1.0`, `digest-v0.1.0`, `proxy-status-v0.1.0`,
`client-cert-v0.1.0`. A bare `v*` tag is rejected loudly by the
release workflow — there is no legacy path. Publishing is RubyGems
trusted publishing (OIDC, no API token): the workflow's dispatch map
carries a first-publish OWNER entry for each gem until that gem's
first release lands. First 0.1.0 releases are cut after each gem's
documentation pass; after that, tags are cut by hand at landing.

See the gem READMEs under `gems/` for installation, quickstart, and
the exact guarantees each gem makes.

## Development

```
bundle install
bundle exec sus        # every gem's suite (config/sus.rb routes gems/*/lib + gems/*/test)
bundle exec rubocop
```

CI (`.github/workflows/ci.yml`): spec matrix on Ruby 3.4/4.0, lint,
the per-gem build loop (`gem build` from each `gems/*/` directory —
nested gemspecs are unbuildable from the repo root), and a security
audit. `script/verify-packaged.rb` proves a built package carries its
require path from outside the checkout.
