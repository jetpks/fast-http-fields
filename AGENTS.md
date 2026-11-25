# AGENTS.md

Standing context for agents working in this repository.

## Commands

```bash
bundle install
bundle exec sus        # every gem's suite — config/sus.rb routes gems/*/lib + gems/*/test
bundle exec rubocop
(cd gems/sfv && gem build fast-sfv.gemspec)   # build a gem from ITS directory — the repo-root form is RubyGems-impossible for nested gemspecs
ruby script/verify-packaged.rb fast-sfv       # packaged-gem verify: isolated GEM_HOME, require from outside the checkout
```

## Layout

- One releasable gem per `gems/<name>/` directory, underscored
  (`gems/proxy_status`, `gems/client_cert`); require leaf
  `fast/<underscored>`. The root `Gemfile` (gemspec glob),
  `config/sus.rb`, CI's build loop, the release dispatch map, and
  `script/verify-packaged.rb` all cover the five planned gems already —
  a new gem directory needs no machinery edit.
- Release tags are per gem, `<prefix>-v<semver>` (prefixes: `sfv`,
  `priority`, `digest`, `proxy-status`, `client-cert`). A bare `v*` tag
  is rejected loudly by release.yml.

## Style Rules

- 2-space indentation; `# frozen_string_literal: true` on every source
  file; double-quoted strings.
- Pure Ruby, no runtime dependencies (fast-sfv is the substrate; the
  four dependents declare it as their only runtime dependency — BRIEF
  strictness, stdlib `digest` aside).
- Hand-rolled byte-index scanners on the hot path (no regex-per-token);
  frozen immutable value objects.

## Test Rules

- Use `sus` + `covered` as the test framework (never rspec — allocation
  measurement must stay clean).
- Tests are terse, exercising public interfaces only.
- No mock/stub of the class under test.

## Local Reference Sources

- RFC corpus (all seven, plaintext): `~/architect/spaces/20261124-fast-fields/build/corpus/`
- Family precedents: `~/architect/spaces/20261124-fast-fields/repos/{fast-llm,fast-uuid,fast-prometheus,fast-protowire}`
