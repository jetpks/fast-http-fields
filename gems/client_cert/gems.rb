# frozen_string_literal: true

source "https://rubygems.org"

# The benchmark bundle, separate from the monorepo root Gemfile (the
# fast-sfv pattern): benchmark-ips never enters the CI or the test
# bundle — it lives only here, behind an explicit BUNDLE_GEMFILE.
# fast-client-cert has no interop peers (no reference RFC 9440 stack
# exists to test against), so the bundle carries the timing harness
# and the published substrate alone. The gems stage offline from the
# gitignored vendor/client-cert-cache at the repo root; install from
# this directory and run the benchmark from the repo root:
#
#   BUNDLE_CACHE_PATH=../../vendor/client-cert-cache \
#     BUNDLE_GEMFILE=gems.rb bundle install --local
#   BUNDLE_GEMFILE=gems/client_cert/gems.rb bundle exec ruby \
#     gems/client_cert/benchmark/client_cert.rb
#
# The pinned fast-sfv is the published 0.2.1 artifact — the substrate
# the benchmark parses and emits through — and not a path entry into
# the sibling checkout (a path form would expand the checkout into
# the cache as an unpacked tree, a stale-copy hazard).

gemspec

group :benchmark do
  # The timing harness (https://github.com/ruby/benchmark-ips, MIT) —
  # stages from the same gitignored cache; never a runtime dependency.
  gem "benchmark-ips", "2.15.1"
  # The published substrate this gem's fields parse and emit through —
  # the same 0.2.1 artifact the released gem depends on. Never a
  # comparator, never a runtime dependency beyond the gemspec's own.
  gem "fast-sfv", "0.2.1"
end
