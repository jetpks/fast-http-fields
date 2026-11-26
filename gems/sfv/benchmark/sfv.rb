# frozen_string_literal: true

# Serialize and parse against the reference: starry, the RFC 8941
# implementation this benchmark compares against — a reference
# comparison, not a ranking. The numbers hold US to OUR budgets (the
# objects/call column); starry is credited as the reference and is a
# dev-only comparator, never a runtime dependency. The compared surface
# is the RFC 8941 subset both libraries implement. benchmark-ips; quick
# mode with BENCH_QUICK=1. Two runtime modes are reportable: the plain
# interpreter (the no-JIT floor) and --yjit (the compiling runtime, the
# common production configuration) — the ruby banner records which ran.
#
#   bundle exec ruby benchmark/sfv.rb
#   BENCH_QUICK=1 bundle exec ruby benchmark/sfv.rb
#   bundle exec ruby --yjit benchmark/sfv.rb
#
# Run from the repo root via the benchmark bundle (gems/sfv/gems.rb):
#
#   BENCH_QUICK=1 BUNDLE_GEMFILE=gems/sfv/gems.rb bundle exec ruby \
#     gems/sfv/benchmark/sfv.rb
#   BUNDLE_GEMFILE=gems/sfv/gems.rb bundle exec ruby --yjit \
#     gems/sfv/benchmark/sfv.rb

require "benchmark/ips"
require "starry"
require_relative "../lib/fast/sfv"

ITEM_SAMPLE = "2;foourl=\"https://foo.example.com/\""
LIST_SAMPLE = "(\"foo\" \"bar\");a=1, sugar, 42"
DICT_SAMPLE = "a=1, b;foo=bar, c=(1 2)"
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

# Each Fast::SFV operation beside the starry call it replaces: the three
# parse entry points against starry's, the three emit entry points
# against starry's single serialize on starry's own parsed values.
our_item = Fast::SFV.parse_item(ITEM_SAMPLE)
our_list = Fast::SFV.parse_list(LIST_SAMPLE)
our_dict = Fast::SFV.parse_dict(DICT_SAMPLE)
starry_item = Starry.parse_item(ITEM_SAMPLE)
starry_list = Starry.parse_list(LIST_SAMPLE)
starry_dict = Starry.parse_dictionary(DICT_SAMPLE)

operations = {
  "Fast::SFV.parse_item" => -> { Fast::SFV.parse_item(ITEM_SAMPLE) },
  "Starry.parse_item" => -> { Starry.parse_item(ITEM_SAMPLE) },
  "Fast::SFV.parse_list" => -> { Fast::SFV.parse_list(LIST_SAMPLE) },
  "Starry.parse_list" => -> { Starry.parse_list(LIST_SAMPLE) },
  "Fast::SFV.parse_dict" => -> { Fast::SFV.parse_dict(DICT_SAMPLE) },
  "Starry.parse_dictionary" => -> { Starry.parse_dictionary(DICT_SAMPLE) },
  "Fast::SFV.serialize_item" => -> { Fast::SFV.serialize_item(our_item) },
  "Starry.serialize (item)" => -> { Starry.serialize(starry_item) },
  "Fast::SFV.serialize_list" => -> { Fast::SFV.serialize_list(our_list) },
  "Starry.serialize (list)" => -> { Starry.serialize(starry_list) },
  "Fast::SFV.serialize_dict" => -> { Fast::SFV.serialize_dict(our_dict) },
  "Starry.serialize (dictionary)" => -> { Starry.serialize(starry_dict) }
}

puts "#{RUBY_DESCRIPTION}; fast-sfv #{Fast::SFV::VERSION}; starry #{Starry::VERSION}"
puts "starry is the RFC 8941 reference implementation: a reference comparison, not a ranking."

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
