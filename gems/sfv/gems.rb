# frozen_string_literal: true

source "https://rubygems.org"

# The benchmark bundle, separate from the root Gemfile (fast-uuid's
# pattern): the comparator never enters the CI or the test bundle — it
# lives only here, behind an explicit BUNDLE_GEMFILE. The bench gems
# stage offline from the gitignored vendor/cache (the spec-frozen kit);
# run from the repo root:
#
#   BUNDLE_GEMFILE=gems/sfv/gems.rb bundle install --local
#   BENCH_QUICK=1 BUNDLE_GEMFILE=gems/sfv/gems.rb bundle exec ruby \
#     gems/sfv/benchmark/sfv.rb

gemspec

group :benchmark do
  # The timing harness (https://github.com/ruby/benchmark-ips, MIT).
  gem "benchmark-ips", "2.15.1"
  # starry (https://github.com/takemar/starry, MIT) — the RFC 8941
  # reference implementation this benchmark compares against. Never a
  # runtime dependency.
  gem "starry", "0.2.0"
end
