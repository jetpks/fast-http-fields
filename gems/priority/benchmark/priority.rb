# frozen_string_literal: true

# The fast-priority benchmark: the eight paths whose allocation budgets
# test/fast/priority/allocations.rb freezes, each on that test's own
# input, in both runtime modes — the plain interpreter (the no-JIT
# floor) and YJIT (the compiling runtime, the common production
# configuration); the ruby banner records which ran. benchmark-ips;
# quick mode with BENCH_QUICK=1.
#
# There is no comparator row: no other Ruby implementation of RFC 9218
# exists — starry, the fast-http-fields family's reference comparator
# for fast-sfv, implements the Structured Fields substrate, not this
# field. The numbers hold fast-priority to its own budgets: the
# objects/call column matches the frozen budget inputs, and it is the
# column the tests catch; i/s is indicative, never contractual.
#
#   bundle exec ruby benchmark/priority.rb
#   BENCH_QUICK=1 bundle exec ruby benchmark/priority.rb
#   bundle exec ruby --yjit benchmark/priority.rb
#
# Run from the repo root via the gem's own bundle
# (gems/priority/gems.rb):
#
#   BENCH_QUICK=1 BUNDLE_GEMFILE=gems/priority/gems.rb bundle exec \
#     ruby gems/priority/benchmark/priority.rb
#   BUNDLE_GEMFILE=gems/priority/gems.rb bundle exec ruby --yjit \
#     gems/priority/benchmark/priority.rb

require "benchmark/ips"
require_relative "../lib/fast/priority"

PARSE_SAMPLE = "u=5, i"
MALFORMED_SAMPLE = "!!"
H2_PAYLOAD = (["00000005"].pack("H*") << "u=5, i")
H3_PAYLOAD = (["04"].pack("H*") << "u=5, i")
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

# The eight budget paths, each on its budget's own input: the two
# parses (the malformed fall shares the parse shape), the emit, the
# merge, and the two codecs in both directions.
priority = Fast::Priority.parse(PARSE_SAMPLE)
emitted = Fast::Priority.parse("u=1, i")
merged_right = Fast::Priority.parse("u=1")

operations = {
  "Fast::Priority.parse" => -> { Fast::Priority.parse(PARSE_SAMPLE) },
  "Fast::Priority.parse (malformed)" => -> { Fast::Priority.parse(MALFORMED_SAMPLE) },
  "Parameters#to_s" => -> { priority.to_s },
  "Parameters#merge" => -> { priority.merge(merged_right) },
  "H2.encode_payload" => -> { Fast::Priority::H2.encode_payload(5, emitted) },
  "H2.decode_payload" => -> { Fast::Priority::H2.decode_payload(H2_PAYLOAD) },
  "H3.encode_payload" => -> { Fast::Priority::H3.encode_payload(4, emitted) },
  "H3.decode_payload" => -> { Fast::Priority::H3.decode_payload(H3_PAYLOAD) }
}

puts "#{RUBY_DESCRIPTION}; fast-priority #{Fast::Priority::VERSION}"
puts "the numbers hold fast-priority to its own budgets (the objects/call column); i/s is indicative"

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
