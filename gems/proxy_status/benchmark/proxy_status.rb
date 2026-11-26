# frozen_string_literal: true

# The fast-proxy-status benchmark: the 27 paths whose allocation
# budgets test/fast/proxy_status/allocations.rb freezes — the ten
# Proxy-Status paths, the ten Cache-Status paths and the seven
# TargetedCacheControl paths — each on that test's own input (the
# RFCs' own worked examples where one exists: the RFC 9209 §2
# two-intermediary list, the RFC 9211 §3 two-layer and three-line
# lists, the RFC 9213 §3.1 directive values, the RFC 9209 §2
# trailer-promotion pair). One row per budget test, the same inputs,
# so the objects/call column and the frozen budgets are one
# discipline. Both runtime modes run: the plain interpreter (the
# no-JIT floor) and YJIT (the compiling runtime, the common
# production configuration); the ruby banner records which ran.
# benchmark-ips; quick mode with BENCH_QUICK=1.
#
# There is no comparator row: no other Ruby implementation of RFC
# 9209, 9211 or 9213 exists — starry, the fast-http-fields family's
# reference comparator for fast-sfv, implements the Structured Fields
# substrate, not these fields. The numbers hold fast-proxy-status to
# its own budgets: the objects/call column matches the frozen budget
# inputs, and it is the column the tests catch; i/s is indicative,
# never contractual.
#
#   bundle exec ruby benchmark/proxy_status.rb
#   BENCH_QUICK=1 bundle exec ruby benchmark/proxy_status.rb
#   bundle exec ruby --yjit benchmark/proxy_status.rb
#
# Run from the repo root via the gem's own bundle
# (gems/proxy_status/gems.rb):
#
#   BENCH_QUICK=1 BUNDLE_GEMFILE=gems/proxy_status/gems.rb bundle \
#     exec ruby gems/proxy_status/benchmark/proxy_status.rb
#   BUNDLE_GEMFILE=gems/proxy_status/gems.rb bundle exec ruby --yjit \
#     gems/proxy_status/benchmark/proxy_status.rb

require "benchmark/ips"
require_relative "../lib/fast/proxy_status"

PROXY_SAMPLE = "revproxy1.example.net, ExampleCDN"  # the RFC 9209 §2 two-intermediary example
MALFORMED_SAMPLE = "!!"
MEMBER_FALL_SAMPLE = "ExampleCDN, 5"
PROMOTE_HEADER = "SomeOtherProxy, ThisProxy"        # the RFC 9209 §2 trailer example
PROMOTE_TRAILER = "ThisProxy; error=read_timeout"
CACHE_TWO_LAYER = 'OriginCache; hit; ttl=1100, "CDN Company Here"; hit; ttl=545'  # the RFC 9211 §3 two-layer example
CACHE_THREE_LINES = ["ReverseProxyCache; hit",
                     "ForwardProxyCache; fwd=uri-miss; collapsed; stored",
                     "BrowserCache; fwd=uri-miss"]  # the RFC 9211 §3 three-layer example
CACHE_SAMPLE = "ExampleCache; hit; ttl=376"         # the RFC 9211 §3 polite-cache example
DIRECTIVE_SAMPLE = "max-age=600, no-store"          # the RFC 9213 §3.1 directive values
FLAGGED_SAMPLE = "max-age=60.5"                     # a Decimal where the §2.1 mapping says Integer
QUICK = ENV["BENCH_QUICK"]

# One settled call's object count, GC off over the timed batch.
def objects_per_call(call, times = 10_000)
  call.call
  GC.start
  GC.disable
  before = GC.stat(:total_allocated_objects)
  times.times { call.call }
  (GC.stat(:total_allocated_objects) - before) / times.to_f
ensure
  GC.enable
end

# The budget paths on their budget inputs — the two List fields'
# parses (clean, malformed fall, member-violation fall, strict,
# mirror), the member constructions, the two append forms, the
# promote, the emits; then the targeted field's parses (clean,
# malformed fall, the flagged leniency, strict, mirror), its
# construction and its emit.
proxy_field = Fast::ProxyStatus.parse(PROXY_SAMPLE)
cache_field = Fast::CacheStatus.parse(CACHE_TWO_LAYER)
targeted_field = Fast::TargetedCacheControl.parse(DIRECTIVE_SAMPLE)
proxy_held = Fast::ProxyStatus.parse("a, b")
cache_held = Fast::CacheStatus.parse("a; hit")
hop = Fast::SFV::Token.new("x")
cache_member = Fast::SFV::Token.new("c")
targeted_members = { "max-age" => 600 }

operations = {
  "ProxyStatus.parse" => -> { Fast::ProxyStatus.parse(PROXY_SAMPLE) },
  "ProxyStatus.parse (malformed)" => -> { Fast::ProxyStatus.parse(MALFORMED_SAMPLE) },
  "ProxyStatus.parse (member fall)" => -> { Fast::ProxyStatus.parse(MEMBER_FALL_SAMPLE) },
  "ProxyStatus.parse!" => -> { Fast::ProxyStatus.parse!(PROXY_SAMPLE) },
  "ProxyStatus.valid?" => -> { Fast::ProxyStatus.valid?(PROXY_SAMPLE) },
  "ProxyStatus::Hop.new" => -> { Fast::ProxyStatus::Hop.new(hop) },
  "ProxyStatus#append (held)" => -> { proxy_held.append(hop) },
  "ProxyStatus.append" => -> { Fast::ProxyStatus.append("a, b", hop) },
  "ProxyStatus.promote" => -> { Fast::ProxyStatus.promote(PROMOTE_HEADER, PROMOTE_TRAILER) },
  "ProxyStatus#to_s" => -> { proxy_field.to_s },
  "CacheStatus.parse" => -> { Fast::CacheStatus.parse(CACHE_TWO_LAYER) },
  "CacheStatus.parse (three-line)" => -> { Fast::CacheStatus.parse(CACHE_THREE_LINES) },
  "CacheStatus.parse (malformed)" => -> { Fast::CacheStatus.parse(MALFORMED_SAMPLE) },
  "CacheStatus.parse (member fall)" => -> { Fast::CacheStatus.parse("ExampleCache, 5") },
  "CacheStatus.parse!" => -> { Fast::CacheStatus.parse!(CACHE_SAMPLE) },
  "CacheStatus.valid?" => -> { Fast::CacheStatus.valid?(CACHE_TWO_LAYER) },
  "CacheStatus::Cache.new" => -> { Fast::CacheStatus::Cache.new(hop) },
  "CacheStatus#append (held)" => -> { cache_held.append(cache_member) },
  "CacheStatus.append" => -> { Fast::CacheStatus.append(CACHE_SAMPLE, hop) },
  "CacheStatus#to_s" => -> { cache_field.to_s },
  "TargetedCacheControl.parse" => -> { Fast::TargetedCacheControl.parse(DIRECTIVE_SAMPLE) },
  "TargetedCacheControl.parse (malformed)" => -> { Fast::TargetedCacheControl.parse(MALFORMED_SAMPLE) },
  "TargetedCacheControl.parse (flagged)" => -> { Fast::TargetedCacheControl.parse(FLAGGED_SAMPLE) },
  "TargetedCacheControl.parse!" => -> { Fast::TargetedCacheControl.parse!(DIRECTIVE_SAMPLE) },
  "TargetedCacheControl.valid?" => -> { Fast::TargetedCacheControl.valid?(DIRECTIVE_SAMPLE) },
  "TargetedCacheControl.new" => -> { Fast::TargetedCacheControl.new(targeted_members) },
  "TargetedCacheControl#to_s" => -> { targeted_field.to_s }
}

puts "#{RUBY_DESCRIPTION}; fast-proxy-status #{Fast::ProxyStatus::VERSION}"
puts "the numbers hold fast-proxy-status to its own budgets (the objects/call column); i/s is indicative"

report = Benchmark.ips do |x|
  x.quiet = true
  x.config(time: QUICK ? 0.5 : 5, warmup: QUICK ? 0.2 : 1)
  operations.each { |name, call| x.report(name, &call) }
end

# The doc's results table: operation, comma-grouped i/s, ±% and objects/call.
def grouped(number)
  number.round.to_s.gsub(/(\d)(?=(\d{3})+\z)/, "\\1,")
end

puts "| operation | i/s | ±% | objects/call |"
puts "|---|---|---|---|"
report.entries.each do |entry|
  objects = objects_per_call(operations.fetch(entry.label))
  error = entry.stats.error / entry.ips * 100
  puts format("| %<label>s | %<ips>s | %<error>.2f | %<objects>.2f |",
              label: entry.label, ips: grouped(entry.ips), error: error, objects: objects)
end
