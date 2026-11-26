# frozen_string_literal: true

# The fast-digest benchmark: the eight paths whose allocation budgets
# test/fast/digest/allocations.rb freezes, each on that test's own
# input, plus the sibling fields that share the machinery (the four
# fields are one Dictionary parse and one emit through the same
# Field code, so their rows answer alike). Both runtime modes run:
# the plain interpreter (the no-JIT floor) and YJIT (the compiling
# runtime, the common production configuration); the ruby banner
# records which ran. benchmark-ips; quick mode with BENCH_QUICK=1.
#
# There is no comparator row: no other Ruby implementation of RFC
# 9530 exists — starry, the fast-http-fields family's reference
# comparator for fast-sfv, implements the Structured Fields
# substrate, not these fields. The numbers hold fast-digest to its
# own budgets: the objects/call column matches the frozen budget
# inputs, and it is the column the tests catch; i/s is indicative,
# never contractual.
#
#   bundle exec ruby benchmark/digest.rb
#   BENCH_QUICK=1 bundle exec ruby benchmark/digest.rb
#   bundle exec ruby --yjit benchmark/digest.rb
#
# Run from the repo root via the gem's own bundle
# (gems/digest/gems.rb):
#
#   BENCH_QUICK=1 BUNDLE_GEMFILE=gems/digest/gems.rb bundle exec \
#     ruby gems/digest/benchmark/digest.rb
#   BUNDLE_GEMFILE=gems/digest/gems.rb bundle exec ruby --yjit \
#     gems/digest/benchmark/digest.rb

require "benchmark/ips"
require_relative "../lib/fast/digest"

INTEGRITY_SAMPLE = "sha-256=:RK/0qy18MlBSVnWgjwz6lZEWjP/lF5HF9bvEF8FabDg=:"  # the Appendix B.1 example
MALFORMED_SAMPLE = "!!"
PREFERENCE_SAMPLE = "sha-512=3, sha-256=10, unixsum=0"
COMPUTE_BODY = "the bytes to hash"
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

# The budget paths on their budget inputs — the integrity parse, its
# malformed fall, the preference parse, the emit, the compute, the
# .of compute-and-construct, the strict parse and the valid? mirror —
# with each field's sibling parse and the preference emit beside them.
repr = Fast::Digest::ReprDigest.parse(INTEGRITY_SAMPLE)
want = Fast::Digest::WantReprDigest.parse(PREFERENCE_SAMPLE)

operations = {
  "ContentDigest.parse" => -> { Fast::Digest::ContentDigest.parse(INTEGRITY_SAMPLE) },
  "ReprDigest.parse" => -> { Fast::Digest::ReprDigest.parse(INTEGRITY_SAMPLE) },
  "ReprDigest.parse (malformed)" => -> { Fast::Digest::ReprDigest.parse(MALFORMED_SAMPLE) },
  "WantContentDigest.parse" => -> { Fast::Digest::WantContentDigest.parse(PREFERENCE_SAMPLE) },
  "WantReprDigest.parse" => -> { Fast::Digest::WantReprDigest.parse(PREFERENCE_SAMPLE) },
  "ReprDigest#to_s" => -> { repr.to_s },
  "WantReprDigest#to_s" => -> { want.to_s },
  "Fast::Digest.compute" => -> { Fast::Digest.compute("sha-256", COMPUTE_BODY) },
  "ReprDigest.of" => -> { Fast::Digest::ReprDigest.of("sha-256", COMPUTE_BODY) },
  "ReprDigest.parse!" => -> { Fast::Digest::ReprDigest.parse!(INTEGRITY_SAMPLE) },
  "WantReprDigest.valid?" => -> { Fast::Digest::WantReprDigest.valid?(PREFERENCE_SAMPLE) }
}

puts "#{RUBY_DESCRIPTION}; fast-digest #{Fast::Digest::VERSION}"
puts "the numbers hold fast-digest to its own budgets (the objects/call column); i/s is indicative"

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
