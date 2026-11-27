# frozen_string_literal: true

source "https://rubygems.org"

# The interop bundle, separate from the monorepo root Gemfile (the
# fast-prometheus precedent): the protocol-http2 reference framing
# stack runs as a TEST-GROUP peer in THIS bundle only — never a
# runtime dependency of the gem (the gemspec declares fast-sfv alone).
# The peers stage offline from the gitignored vendor/priority-cache
# at the repo root; run the interop suite from this directory:
#
#   BUNDLE_CACHE_PATH=../../vendor/priority-cache \
#     BUNDLE_GEMFILE=gems.rb bundle install --local
#   BUNDLE_CACHE_PATH=../../vendor/priority-cache \
#     BUNDLE_GEMFILE=gems.rb bundle exec sus \
#     test/fast/priority/interop.rb
#
# The pinned fast-sfv is the published 0.2.1 artifact — the same thing
# script/verify-packaged.rb proves — and not a path entry into the
# sibling checkout (a path form would expand the checkout into the
# cache as an unpacked tree, a stale-copy hazard).

gemspec

group :test do
  gem "sus", "0.38.0"
  gem "fast-sfv", "0.2.1"
  # protocol-http2 (https://github.com/socketry/protocol-http2, MIT)
  # — the reference HTTP/2 framing stack the interop suite exercises
  # in both directions. Never a runtime dependency.
  gem "protocol-http2", "0.29.2"
end

group :benchmark do
  # The timing harness (https://github.com/ruby/benchmark-ips, MIT) —
  # stages from the same gitignored cache as the peers above; never a
  # runtime dependency. Runs the perf page's both-mode measurements:
  #
  #   BUNDLE_GEMFILE=gems/priority/gems.rb bundle exec ruby \
  #     gems/priority/benchmark/priority.rb
  #   BUNDLE_GEMFILE=gems/priority/gems.rb bundle exec ruby --yjit \
  #     gems/priority/benchmark/priority.rb
  gem "benchmark-ips", "2.15.1"
end
