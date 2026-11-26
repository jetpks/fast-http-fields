# frozen_string_literal: true

source "https://rubygems.org"

# The benchmark bundle, separate from the monorepo root Gemfile (the
# fast-sfv pattern): benchmark-ips never enters the CI or the test
# bundle — it lives only here, behind an explicit BUNDLE_GEMFILE.
# fast-digest has no interop peers (no reference RFC 9530 stack
# exists to test against), so the bundle carries the timing harness
# and the published substrate alone. The gems stage offline from the
# gitignored vendor/digest-cache at the repo root; install from this
# directory and run the benchmark from the repo root:
#
#   BUNDLE_CACHE_PATH=../../vendor/digest-cache \
#     BUNDLE_GEMFILE=gems.rb bundle install --local
#   BUNDLE_GEMFILE=gems/digest/gems.rb bundle exec ruby \
#     gems/digest/benchmark/digest.rb
#
# The pinned fast-sfv is the published 0.1.1 artifact — the substrate
# the benchmark parses and emits through — and not a path entry into
# the sibling checkout (a path form would expand the checkout into
# the cache as an unpacked tree, a stale-copy hazard).

gemspec

group :benchmark do
  # The timing harness (https://github.com/ruby/benchmark-ips, MIT) —
  # stages from the same gitignored cache; never a runtime dependency.
  gem "benchmark-ips", "2.15.1"
  # The published substrate this gem's fields parse and emit through —
  # the same 0.1.1 artifact script/verify-packaged.rb proves. Never a
  # comparator, never a runtime dependency beyond the gemspec's own.
  gem "fast-sfv", "0.1.1"
end
