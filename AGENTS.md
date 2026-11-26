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
  four dependents declare it as their only runtime dependency —
  stdlib `digest` aside).
- Hand-rolled byte-index scanners on the hot path (no regex-per-token);
  frozen immutable value objects.

## Code Discipline

Binding for every change to this repo.

### Comments

- Never reference documents that live outside this repo — internal
  specs, decisions, or rulings. A comment explains itself from the
  code, the RFC, and the tests.
- Do cite the RFC where the code implements a specific grammar step
  (parser.rb's §4.2.x and serializer.rb's §4.1.x comments are the
  pattern).

### Idiomaticity inside the allocation budgets

The allocation budgets (`test/fast/*/allocations.rb`) are contract.
Within them, write idiomatic Ruby:

- Binary buffers are `"".b`, never `String.new` — the same
  ASCII-8BIT string, spelled as the idiom.
- A stdlib predicate beats a hand-rolled scan when it states the same
  fact: `String#ascii_only?` for the ASCII pre-check, with the byte
  walk kept on the failure path where the error needs the offset.
- Type dispatch is `case`/`when`, not an if/elsif `is_a?` chain.
- Constants read across classes get local aliases
  (`PERIOD = Parser::PERIOD`), not mid-code `Parser::X` references.

Measured traps — idiomatic forms that allocate, rejected here:

- `each_with_index`: two objects per Array call, a pair Array per Hash
  entry — separator loops carry a first-member flag instead.
- Multi-value returns pack an Array per call; phase extractions
  return one value or none.

### Method length

- Methods read as named phases; ~30 code lines is the working
  ceiling. `emit_decimal`'s scan-and-round block is the one deliberate
  exception (~40): a single numeric algorithm that cannot split
  without allocating.
- Extract at phase seams (scan / validate / convert / emit); keep
  every raise at its exact position in the byte sequence — error
  offsets are pinned by the tests.
- Hot byte-walk `while` loops stay manual (allocation-free
  iteration): extract around them, never inside them.

## Test Rules

- Use `sus` + `covered` as the test framework (never rspec — allocation
  measurement must stay clean).
- Tests are terse, exercising public interfaces only.
- No mock/stub of the class under test.

## Local Reference Sources

- RFC corpus (all seven, plaintext): `~/architect/spaces/20261124-fast-fields/build/corpus/`
- Family precedents: `~/architect/spaces/20261124-fast-fields/repos/{fast-llm,fast-uuid,fast-prometheus,fast-protowire}`
