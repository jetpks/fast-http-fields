#!/usr/bin/env ruby
# frozen_string_literal: true

# Adversarial fuzz harness for the fast-http-fields family.
#
# Oracles, in authority order:
#   1. the documented contracts (error classes, #offset Integer ranges,
#      never-raise, deep-frozen) — machine-checked, no second implementation
#   2. metamorphic laws (round-trip, canonicalization idempotence,
#      valid?/parse! coherence, regions/parse agreement, array-combining
#      equivalence, lenient-to_s strict reparse)
#   3. Ref — an independent RFC 9651 §4.1 serializer written for this harness
#   4. starry 0.2.0 — a DIFFERENTIAL PEER on the RFC 8941 subset only; every
#      disagreement is recorded unadjudicated and ruled against the RFC in
#      triage, never on starry's say-so
#
# Usage: ruby script/fuzz.rb <campaign> [iterations] [seed] [--starry-lib <dir>]
#
# Campaigns:
#   bootstrap   — the vendored httpwg corpus (gems/sfv/test/corpus): parse
#                 == expected trees, the reference serializer byte-agreement,
#                 and (with the starry peer) the peer bootstrap gate
#   contract    — mutation fuzz (byte ops, encoding matrix, line arrays) ×
#                 every parse surface: raise classes, offset bounds,
#                 valid? coherence, frozen trees, round-trips, regions
#                 agreement, combining equivalence, the dependents
#   generate    — grammar-aware trees → text → parse equality, canonical
#                 byte-agreement (impl vs ref), idempotence, peer
#                 differential, full substrate + dependent batteries
#   regions     — region spans/ordering/counts, key-text agreement, member
#                 value-slice reparse equality
#   diff        — starry accept/reject + canonical differential on the
#                 8941∩9651 subset (requires the starry peer)
#   emit        — hostile values into every emit/construction boundary +
#                 mutated-tree emit-never-lies (fixed-point + impl-vs-ref)
#   frames      — random/mutated binary payloads through H2/H3 decode
#                 (frame invariants, error offsets), encode boundary
#                 matrix, non-minimal varint forms
#   pem         — PEM round-trips (single + chain), mutated armor/payload
#                 contracts, fail-closed parses
#   perf        — pathological shapes (50KB→1.6MB): wall time and
#                 linearity (2× size ⇒ ≤8× cost)
#   concurrent  — thread raises, cross-run determinism
#
# [iterations] defaults to 10_000 and [seed] to 20261127; a run is
# deterministic in (campaign, iterations, seed).
#
# The starry peer is OPTIONAL and never vendored: point STARRY_LIB or
# --starry-lib at a directory that contains starry.rb (a starry gem's
# lib/ dir) to enable the differential checks. Without it every
# starry-dependent check is SKIPPED with a loud notice — a skip is not a
# pass and not a failure. A configured directory that does not load
# starry aborts the run.
#
# Violations are appended to tmp/violations.jsonl (gitignored); each run
# prints its own summary line on stdout.

REPO = File.expand_path("..", __dir__)
CORPUS_DIR = File.join(REPO, "gems", "sfv", "test", "corpus")
OUT = File.join(REPO, "tmp", "violations.jsonl")

%w[sfv priority digest proxy_status client_cert].each { |g| $LOAD_PATH.unshift(File.join(REPO, "gems", g, "lib")) }
require "fast/sfv"
require "fast/priority"
require "fast/digest"
require "fast/proxy_status"
require "fast/client_cert"
require "json"
require "benchmark"
require "fileutils"

FileUtils.mkdir_p(File.dirname(OUT))

# The starry peer loads only from an explicitly named directory (the flag
# or the env var) and never from an unrelated installed gem: a run without
# the peer is a loud SKIP, a named directory that does not provide starry
# is a hard abort. Memoized — the notice prints once per process.
def load_starry
  return @load_starry if defined?(@load_starry)

  @load_starry = if STARRY_DIR.nil?
                   puts "SKIP: starry peer not configured — starry-dependent checks skipped " \
                        "(point STARRY_LIB or --starry-lib at a dir containing starry.rb)"
                   nil
                 else
                   unless File.file?(File.join(STARRY_DIR, "starry.rb"))
                     abort "fuzz: #{STARRY_DIR.inspect} does not contain starry.rb — fix STARRY_LIB/--starry-lib"
                   end
                   $LOAD_PATH.unshift(STARRY_DIR)
                   begin
                     require "starry"
                   rescue LoadError => e
                     abort "fuzz: starry.rb in #{STARRY_DIR.inspect} failed to load (#{e.class}: #{e.message})"
                   end
                   puts "starry: differential peer loaded from #{STARRY_DIR}"
                   Starry
                 end
end

# ---------------------------------------------------------------------------
# Violation recording
# ---------------------------------------------------------------------------

class FuzzInternalError < StandardError; end

module Viol
  KEY_COUNTS = Hash.new(0)
  MUTEX = Mutex.new
  STORE_LIMIT = 500

  def self.record(campaign, check, detail, context)
    MUTEX.synchronize do
      key = "#{check}|#{detail.to_s.lines.first.to_s.chomp}"
      KEY_COUNTS[key] += 1
      return if KEY_COUNTS.size > STORE_LIMIT

      entry = { c: campaign, k: key, n: KEY_COUNTS[key], d: detail.to_s, ctx: context.to_s }
      File.open(OUT, "a") { |f| f.puts(JSON.generate(entry)) }
    end
  end

  def self.counts
    KEY_COUNTS
  end
end

def combined_size(input)
  case input
  when String then input.bytesize
  when Array
    begin
      input.join(", ").bytesize
    rescue StandardError
      input.sum { |l| l.is_a?(String) ? l.bytesize : 0 } + 2 * (input.size - 1)
    end
  else 0
  end
end

def describe_input(input)
  case input
  when String then "#{input.encoding.name}(#{input.bytesize}) #{input.byteslice(0, 120).inspect}"
  when Array then "Array #{input.map { |l| describe_input(l) }.join(' | ')}"
  else
    defined?(input.class) ? input.class.name : "a classless object"
  end
end

# Runs a block under a raise contract: +allowed+ is the exhaustive list of
# classes the surface's documentation admits. Any other raise is recorded.
# Returns [outcome, value_or_error] with outcome :ok / :doc / :bad.
def try(surface, allowed, input = nil, campaign: CAMPAIGN, ctx: nil)
  result = yield
  [:ok, result]
rescue Exception => e # rubocop:disable Lint/RescueException -- intentional: the contract walker must see every raise
  raise if e.is_a?(Interrupt) || e.is_a?(SystemExit)

  if allowed.any? { |klass| e.is_a?(klass) }
    [:doc, e]
  else
    Viol.record(campaign, "raise-contract",
                "#{surface} raised #{e.class}: #{e.message.to_s.byteslice(0, 160)}",
                "input=#{describe_input(input)} #{ctx}")
    [:bad, e]
  end
end

def check_offset(surface, error, input, campaign: CAMPAIGN, ctx: nil)
  size = combined_size(input)
  offset = error.offset
  return if offset.is_a?(Integer) && offset >= 0 && offset <= size

  Viol.record(campaign, "offset",
              "#{surface} #{error.class} offset=#{offset.inspect} (#{error.message.to_s.byteslice(0, 120)})",
              "input=#{describe_input(input)} combined_size=#{size} #{ctx}")
end

def safe
  [yield, nil]
rescue Exception => e # rubocop:disable Lint/RescueException -- intentional: the contract walker must see every raise
  raise if e.is_a?(Interrupt) || e.is_a?(SystemExit)

  [nil, e]
end

# ---------------------------------------------------------------------------
# Corpus: seeds and expected value trees
# ---------------------------------------------------------------------------

BASE32_ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567"
BASE32_VALUES = Array.new(256, nil).tap do |values|
  BASE32_ALPHABET.each_byte.with_index { |byte, index| values[byte] = index }
end

def decode_base32(text)
  bytes = +"".b
  buffer = 0
  bits = 0
  text.each_byte do |byte|
    break if byte == 0x3D

    value = BASE32_VALUES[byte]
    raise FuzzInternalError, "corpus binary not base32" unless value

    buffer = (buffer << 5) | value
    bits += 5
    if bits >= 8
      bits -= 8
      bytes << ((buffer >> bits) & 0xFF)
    end
  end
  bytes
end

module Tree
  module_function

  def bare(expected)
    case expected
    when Hash
      case expected["__type"]
      when "token" then Fast::SFV::Token.new(expected["value"])
      when "binary" then decode_base32(expected["value"])
      when "date" then Fast::SFV::Date.new(expected["value"])
      when "displaystring" then Fast::SFV::DisplayString.new(expected["value"])
      else raise FuzzInternalError, "unknown corpus bare #{expected.inspect}"
      end
    else expected
    end
  end

  def params(expected)
    expected.to_h { |key, value| [key, bare(value)] }
  end

  def item(expected)
    Fast::SFV::Item.new(bare(expected[0]), params(expected[1]).freeze)
  end

  # A corpus member is an inner list exactly when its value is an Array.
  def member(expected)
    expected[0].is_a?(Array) ? inner_list(expected) : item(expected)
  end

  def inner_list(expected)
    Fast::SFV::InnerList.new(expected[0].map { |i| item(i) }.freeze, params(expected[1]).freeze)
  end

  def top(expected, header_type)
    case header_type
    when "item" then item(expected)
    when "list" then expected.map { |m| member(m) }.freeze
    when "dictionary" then expected.to_h { |key, m| [key, member(m)] }.freeze
    else raise FuzzInternalError, "header_type #{header_type}"
    end
  end
end

def corpus_records
  @corpus_records ||= Dir.glob(File.join(CORPUS_DIR, "*.json")).sort.flat_map do |path|
    JSON.parse(File.read(path)).map { |record| record.merge("file" => File.basename(path)) }
  end
end

# ---------------------------------------------------------------------------
# Ref: an independent RFC 9651 §4.1 serializer (the model oracle)
# ---------------------------------------------------------------------------

module Ref
  INTEGER_MAX = 999_999_999_999_999
  KEY_RE = /\A[a-z*][a-z0-9_\-.*]*\z/
  TOKEN_RE = %r{\A[A-Za-z*][!#$%&'*+\-.^_`|~0-9A-Za-z:/]*\z}

  module_function

  def serialize_top(tree, shape)
    case shape
    when :item then item_string(tree)
    when :list then tree.empty? ? nil : tree.map { |m| member_string(m) }.join(", ")
    when :dictionary then tree.empty? ? nil : tree.map { |k, m| dict_member(k, m) }.join(", ")
    end
  end

  def member_string(member)
    member.is_a?(Fast::SFV::InnerList) ? inner_list_string(member) : item_string(member)
  end

  def item_string(item)
    bare(item.value) + params(item.params)
  end

  def inner_list_string(inner)
    "(#{inner.items.map { |i| item_string(i) }.join(' ')})#{params(inner.params)}"
  end

  def dict_member(key, member)
    validate_key(key)
    if member.is_a?(Fast::SFV::Item) && member.value.equal?(true)
      key + params(member.params)
    else
      "#{key}=#{member_string(member)}"
    end
  end

  def params(params)
    params.map do |key, value|
      validate_key(key)
      value.equal?(true) ? ";#{key}" : ";#{key}=#{bare(value)}"
    end.join
  end

  def validate_key(key)
    raise FuzzInternalError, "ref: bad key #{key.inspect}" unless key.is_a?(String) && KEY_RE.match?(key)
  end

  def bare(value)
    case value
    when Integer
      raise FuzzInternalError, "ref: integer range" unless value.abs <= INTEGER_MAX

      value.to_s
    when Float then decimal(value)
    when Fast::SFV::Token
      raise FuzzInternalError, "ref: bad token" unless TOKEN_RE.match?(value) && !value.empty?

      value
    when String
      if value.encoding == Encoding::ASCII_8BIT
        ":#{[value].pack('m0')}:"
      else
        out = +'"'
        value.each_byte do |byte|
          raise FuzzInternalError, "ref: string byte" if byte < 0x20 || byte > 0x7e

          out << "\\" if [0x22, 0x5C].include?(byte)
          out << byte
        end
        out << '"'
      end
    when true then "?1"
    when false then "?0"
    when Fast::SFV::Date
      "@#{bare(value.value)}"
    when Fast::SFV::DisplayString
      out = +'%"'
      value.value.each_byte do |byte|
        out << if byte == 0x25 || byte == 0x22 || byte < 0x20 || byte > 0x7e
                 format("%%%02x", byte)
               else
                 byte
               end
      end
      out << '"'
    else raise FuzzInternalError, "ref: bad bare #{value.class}"
    end
  end

  # §4.1.5: the shortest round-trip digits of Float#to_s, rounded to three
  # fraction places, ties to even; at most 12 integer digits.
  def decimal(value)
    raise FuzzInternalError, "ref: not finite" unless value.finite?

    text = value.to_s
    m = /\A(-?)(\d+)(?:\.(\d+))?(?:e([+-]?\d+))?\z/.match(text)
    raise FuzzInternalError, "ref: unreadable to_s" unless m

    negative = !m[1].empty?
    int_part = m[2]
    frac_part = m[3] || ""
    exponent = m[4] ? m[4].to_i : 0
    digits = int_part + frac_part
    point = int_part.size + exponent
    mantissa = digits.to_i
    scale = digits.size - point

    if scale > 3
      factor = 10**(scale - 3)
      quotient = mantissa / factor
      remainder = mantissa % factor
      half = factor / 2
      quotient += 1 if remainder > half || (remainder == half && quotient.odd?)
      mantissa = quotient
      scale = 3
    end

    out = format_decimal(negative, mantissa, scale)
    raise FuzzInternalError, "ref: 12 integer digits" if out.match?(/\A\d{13,}\./)

    out
  end

  def format_decimal(negative, mantissa, scale)
    out = +""
    out << "-" if negative && mantissa.positive?
    out << (scale <= 0 ? mantissa.to_s + "0" * -scale : (mantissa / 10**scale).to_s)
    out << "."
    if scale <= 0
      out << "0"
    else
      fraction = mantissa % 10**scale
      text = fraction.zero? ? "0" : fraction.to_s.rjust(scale, "0").sub(/0+\z/, "")
      out << text
    end
    out
  end
end

# ---------------------------------------------------------------------------
# Eq: deep tree equality (class- and encoding-sensitive)
# ---------------------------------------------------------------------------

module Eq
  BINARY = Encoding::ASCII_8BIT

  module_function

  def top(actual, expected, shape)
    case shape
    when :item then member(actual, expected)
    when :list
      actual.is_a?(Array) && expected.is_a?(Array) && actual.size == expected.size &&
        actual.zip(expected).all? { |x, y| member(x, y) }
    when :dictionary
      actual.is_a?(Hash) && expected.is_a?(Hash) && actual.size == expected.size &&
        actual.to_a.zip(expected.to_a).all? { |(k1, v1), (k2, v2)| k1 == k2 && member(v1, v2) }
    else raise FuzzInternalError
    end
  end

  def member(actual, expected)
    case expected
    when Fast::SFV::InnerList
      actual.is_a?(Fast::SFV::InnerList) && actual.items.size == expected.items.size &&
        actual.items.zip(expected.items).all? { |x, y| item(x, y) } && params(actual.params, expected.params)
    when Fast::SFV::Item
      item(actual, expected)
    else false
    end
  end

  def item(actual, expected)
    actual.is_a?(Fast::SFV::Item) && bare(actual.value, expected.value) &&
      params(actual.params, expected.params)
  end

  def params(actual, expected)
    actual.is_a?(Hash) && expected.is_a?(Hash) && actual.size == expected.size &&
      actual.to_a.zip(expected.to_a).all? { |(k1, v1), (k2, v2)| k1 == k2 && bare(v1, v2) }
  end

  def bare(actual, expected)
    case expected
    when Integer then actual.is_a?(Integer) && actual == expected
    when Float then actual.is_a?(Float) && actual == expected
    when Fast::SFV::Token then actual.is_a?(Fast::SFV::Token) && actual == expected
    when String
      if expected.encoding == BINARY
        actual.is_a?(String) && !actual.is_a?(Fast::SFV::Token) && actual.encoding == BINARY &&
          actual == expected
      else
        actual.is_a?(String) && !actual.is_a?(Fast::SFV::Token) && actual.encoding != BINARY &&
          actual == expected
      end
    when true then actual.equal?(true)
    when false then actual.equal?(false)
    when Fast::SFV::Date then actual.is_a?(Fast::SFV::Date) && actual.value == expected.value
    when Fast::SFV::DisplayString
      actual.is_a?(Fast::SFV::DisplayString) && actual.value == expected.value
    else false
    end
  end
end

# Is this value tree inside the RFC 8941 subset the differential peer reads?
# 9651 tokens may carry ":" and "/", 9651 byte sequences may be empty.
def tree_8941?(tree)
  walk = lambda do |v|
    case v
    when Fast::SFV::Token then !v.include?(":") && !v.include?("/")
    when String then v.encoding != Encoding::ASCII_8BIT || !v.empty?
    when Fast::SFV::Item, Fast::SFV::Date, Fast::SFV::DisplayString then walk.call(v.value)
    when Fast::SFV::InnerList then v.items.all? { |i| walk.call(i) }
    when Array then v.all? { |m| walk.call(m) }
    when Hash then v.values.all? { |m| walk.call(m) }
    else true
    end
  end
  walk.call(tree)
end

# ---------------------------------------------------------------------------
# The frozen-tree contract
# ---------------------------------------------------------------------------

def check_frozen(value, surface, input, campaign: CAMPAIGN, ctx: nil)
  walk = lambda do |v, path|
    case v
    when Fast::SFV::Item
      unless v.frozen?
        Viol.record(campaign, "frozen", "#{surface} not frozen at #{path}",
                    "input=#{describe_input(input)} #{ctx}")
      end
      walk.call(v.value, "#{path}.value")
      walk.call(v.params, "#{path}.params")
    when Fast::SFV::InnerList
      unless v.frozen?
        Viol.record(campaign, "frozen", "#{surface} not frozen at #{path}",
                    "input=#{describe_input(input)} #{ctx}")
      end
      walk.call(v.items, "#{path}.items")
      walk.call(v.params, "#{path}.params")
    when Fast::SFV::Date, Fast::SFV::DisplayString
      unless v.frozen?
        Viol.record(campaign, "frozen", "#{surface} not frozen at #{path}",
                    "input=#{describe_input(input)} #{ctx}")
      end
      walk.call(v.value, "#{path}.value")
    when Array
      unless v.frozen?
        Viol.record(campaign, "frozen", "#{surface} not frozen at #{path}",
                    "input=#{describe_input(input)} #{ctx}")
      end
      v.each_with_index { |e, i| walk.call(e, "#{path}[#{i}]") }
    when Hash
      unless v.frozen?
        Viol.record(campaign, "frozen", "#{surface} not frozen at #{path}",
                    "input=#{describe_input(input)} #{ctx}")
      end
      v.each do |k, val|
        unless k.is_a?(String) && k.frozen?
          Viol.record(campaign, "frozen", "#{surface} key not frozen at #{path}",
                      "input=#{describe_input(input)} #{ctx}")
        end
        walk.call(val, "#{path}[#{k.inspect}]")
      end
    when String
      unless v.frozen?
        Viol.record(campaign, "frozen", "#{surface} not frozen at #{path}",
                    "input=#{describe_input(input)} #{ctx}")
      end
    end
  end
  walk.call(value, "result")
end

# ---------------------------------------------------------------------------
# Gen: grammar-aware random value trees (and their Ref wire text)
# ---------------------------------------------------------------------------

module Gen
  ALPHA = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"
  LCALPHA = "abcdefghijklmnopqrstuvwxyz"
  DIGITS = "0123456789"
  TCHAR = "!#$%&'*+-.^_`|~"
  KEYS = %w[u i a b foo key x1 a-b.c d_e *].freeze
  EDGE_INTS = [0, 1, -1, 7, 9, 10, 999, 999_999_999_999_999, -999_999_999_999_999].freeze
  DATE_MAX = 999_999_999_999_999

  module_function

  def key(rng)
    return KEYS.sample(random: rng) if rng.rand(10) < 6

    size = rng.rand(1..8)
    chars = "#{LCALPHA}#{DIGITS}_-.*".chars
    "#{LCALPHA.chars.sample(random: rng)}#{Array.new(size) { chars.sample(random: rng) }.join}"
  end

  def token_text(rng)
    first = "#{ALPHA}*".chars.sample(random: rng)
    body = Array.new(rng.rand(0..10)) { "#{ALPHA}#{DIGITS}#{TCHAR}:/".chars.sample(random: rng) }
    "#{first}#{body.join}"
  end

  def string_text(rng)
    chars = Array.new(rng.rand(0..12)) do
      pick = rng.rand(10)
      if pick < 5 then (0x21..0x7e).to_a.sample(random: rng)
      elsif pick < 7 then 0x20
      elsif pick < 8 then 0x22 # DQUOTE, escaped on the wire
      elsif pick < 9 then 0x5C # backslash, escaped on the wire
      else 0x7e
      end
    end
    chars.pack("C*")
  end

  def bytes_value(rng)
    size = rng.rand(0..16)
    Array.new(size) { rng.rand(256) }.pack("C*")
  end

  def display_string(rng)
    if rng.rand(4) < 3
      chars = Array.new(rng.rand(0..10)) do
        (0x20..0x7e).to_a.reject do |b|
          [0x22, 0x25].include?(b)
        end.sample(random: rng)
      end
      chars.pack("C*")
    else
      Array.new(rng.rand(1..4)) { [0x2603, 0xE9, 0x4E2D, 0x1F600].sample(random: rng) }.pack("U*")
    end
  end

  def decimal_text(rng)
    int_digits = rng.rand(1..12)
    int = Array.new(int_digits) { DIGITS.chars.sample(random: rng) }.join
    int = "0" if int.match?(/\A0\d/)
    frac =
      case rng.rand(4)
      when 0 then ""
      when 1 then ".#{DIGITS.chars.sample(random: rng)}"
      when 2 then ".#{Array.new(2) { DIGITS.chars.sample(random: rng) }.join}"
      else ".#{Array.new(3) { DIGITS.chars.sample(random: rng) }.join}"
      end
    text = "#{int}#{frac}"
    rng.rand(4).zero? ? "-#{text}" : text
  end

  def date_value(rng)
    value = EDGE_INTS.sample(random: rng) + rng.rand(-100..100)
    value.clamp(-DATE_MAX, DATE_MAX)
  end

  def bare(rng, allow_display: true)
    pick = rng.rand(allow_display ? 9 : 8)
    case pick
    when 0 then EDGE_INTS.sample(random: rng)
    when 1 then decimal_text(rng).to_f
    when 2 then string_text(rng)
    when 3 then Fast::SFV::Token.new(token_text(rng))
    when 4 then bytes_value(rng)
    when 5 then rng.rand(2).zero?
    when 6 then Fast::SFV::Date.new(date_value(rng))
    when 7 then Fast::SFV::Date.new(EDGE_INTS.sample(random: rng))
    else Fast::SFV::DisplayString.new(display_string(rng))
    end
  end

  def params(rng)
    return {}.freeze if rng.rand(4).zero?

    count = rng.rand(1..3)
    pairs = count.times.map { [key(rng), rng.rand(3).zero? || bare(rng, allow_display: false)] }
    pairs.to_h.freeze
  end

  def item(rng)
    Fast::SFV::Item.new(bare(rng), params(rng))
  end

  def inner_list(rng)
    count = rng.rand(0..3)
    items = Array.new(count) { Fast::SFV::Item.new(bare(rng, allow_display: false), params(rng)) }
    Fast::SFV::InnerList.new(items.freeze, params(rng))
  end

  def member(rng)
    rng.rand(4).zero? ? inner_list(rng) : item(rng)
  end

  def list(rng)
    count = rng.rand(0..4)
    count.zero? ? [].freeze : Array.new(count) { member(rng) }.freeze
  end

  def dictionary(rng)
    count = rng.rand(0..4)
    dict = {}
    count.times do
      k = key(rng)
      dict[k] = if rng.rand(6).zero?
                  Fast::SFV::Item.new(true, params(rng)) # valueless short form
                else
                  member(rng)
                end
    end
    dict.freeze
  end

  def tree(rng, shape)
    case shape
    when :item then item(rng)
    when :list then list(rng)
    when :dictionary then dictionary(rng)
    end
  end
end

# ---------------------------------------------------------------------------
# Mut: byte-level and structural mutation
# ---------------------------------------------------------------------------

module Mut
  SPECIALS = " \t,;=()\"\\%@?-.:*_'".bytes + [0x00, 0x01, 0x09, 0x0D, 0x7F, 0x80, 0xFF].freeze

  module_function

  def flip(text, rng)
    b = text.b
    return text if b.empty?

    pos = rng.rand(b.bytesize)
    op = rng.rand(10)
    insert = case op
             when 0..2 then SPECIALS.sample(random: rng).chr
             when 3 then b.byteslice(pos, 1).upcase
             when 4 then b.byteslice(pos, 1).downcase
             when 5 then ""
             when 6 then b.byteslice(pos, 1) * rng.rand(1..4)
             when 7 then SPECIALS.sample(random: rng).chr * rng.rand(1..3)
             when 8 then pos + 1 < b.bytesize ? b.byteslice(pos, 2).reverse : b.byteslice(pos, 1)
             else SPECIALS.sample(random: rng).chr + SPECIALS.sample(random: rng).chr
             end
    b.byteslice(0, pos) + insert + b.byteslice(pos + 1, b.bytesize)
  end

  def several(text, rng, count)
    count.times { text = flip(text, rng) }
    text
  end

  def encode_or_self(bytes, encoding, binary: true)
    u = bytes.dup.force_encoding(Encoding::UTF_8)
    out = u.encode(encoding)
    binary ? out.b : out
  rescue StandardError
    bytes
  end

  def reencode(text, rng)
    b = text.b
    case rng.rand(12)
    when 0 then b.dup.force_encoding(Encoding::UTF_8)
    when 1 then b.dup.force_encoding(Encoding::ISO_8859_1)
    when 2 then b.dup.force_encoding(Encoding::US_ASCII)
    when 3 then encode_or_self(b, Encoding::UTF_16LE)
    when 4 then encode_or_self(b, Encoding::UTF_16BE)
    when 5 then encode_or_self(b, Encoding::UTF_32LE)
    when 6 then b.ascii_only? ? encode_or_self(b, Encoding::UTF_16LE, binary: false) : b
    when 7 then b.ascii_only? ? encode_or_self(b, Encoding::UTF_32BE, binary: false) : b
    else b
    end
  end

  def to_lines(text, rng)
    return [text.dup] if text.bytesize < 4 || rng.rand(3).zero?

    points = Array.new(rng.rand(1..2)) { rng.rand(1...text.bytesize) }.uniq.sort
    lines = []
    prev = 0
    points.each do |point|
      lines << text.byteslice(prev, point - prev)
      prev = point
    end
    lines << text.byteslice(prev, text.bytesize - prev)
    lines[0] = reencode(lines[0], rng) if rng.rand(8).zero?
    lines << 5 if rng.rand(40).zero? # non-String member: TypeError is legal
    lines
  end
end

# ---------------------------------------------------------------------------
# Surface checks
# ---------------------------------------------------------------------------

SHAPES = %i[item list dictionary].freeze

def sfv_entry(shape)
  case shape
  when :item then Fast::SFV.method(:parse_item)
  when :list then Fast::SFV.method(:parse_list)
  when :dictionary then Fast::SFV.method(:parse_dict)
  end
end

def sfv_valid(shape)
  case shape
  when :item then Fast::SFV.method(:valid_item?)
  when :list then Fast::SFV.method(:valid_list?)
  when :dictionary then Fast::SFV.method(:valid_dict?)
  end
end

def sfv_regions(shape)
  case shape
  when :item then Fast::SFV.method(:regions_item)
  when :list then Fast::SFV.method(:regions_list)
  when :dictionary then Fast::SFV.method(:regions_dict)
  end
end

def sfv_serialize(shape)
  case shape
  when :item then Fast::SFV.method(:serialize_item)
  when :list then Fast::SFV.method(:serialize_list)
  when :dictionary then Fast::SFV.method(:serialize_dict)
  end
end

def shape_name(shape)
  shape == :dictionary ? :dict : shape
end

# The full substrate check battery for one input.
def check_substrate(input, campaign: CAMPAIGN, ctx: nil)
  SHAPES.each do |shape|
    label = "SFV.parse_#{shape_name(shape)}"
    outcome, parsed = try(label, [Fast::SFV::ParseError, TypeError], input, campaign: campaign, ctx: ctx) do
      sfv_entry(shape).call(input)
    end

    voutcome, v = try("SFV.valid_#{shape_name(shape)}?", [], input, campaign: campaign, ctx: ctx) do
      sfv_valid(shape).call(input)
    end
    if voutcome == :ok
      expected = outcome == :ok
      unless v == expected
        Viol.record(campaign, "valid-coherence",
                    "valid_#{shape_name(shape)} answered #{v.inspect} but parse #{expected ? 'succeeded' : 'raised'}",
                    "input=#{describe_input(input)} #{ctx}")
      end
    end

    next unless outcome == :ok

    check_frozen(parsed, label, input, campaign: campaign, ctx: ctx)

    s1, err = safe { sfv_serialize(shape).call(parsed) }
    if err
      Viol.record(campaign, "roundtrip", "serialize after parse raised #{err.class}: #{err.message}",
                  "input=#{describe_input(input)} #{ctx}")
    elsif s1
      outcome2, reparsed = try("#{label} (reparse of s1)", [Fast::SFV::ParseError], s1, campaign: campaign, ctx: ctx) do
        sfv_entry(shape).call(s1)
      end
      if outcome2 == :ok
        unless Eq.top(reparsed, parsed, shape)
          Viol.record(campaign, "roundtrip", "reparse of canonical form differs from original parse",
                      "input=#{describe_input(input)} s1=#{s1.inspect} #{ctx}")
        end
        s2 = safe { sfv_serialize(shape).call(reparsed) }.first
        if s1 && s2 && s1 != s2
          Viol.record(campaign, "roundtrip", "canonicalization not idempotent: #{s1.inspect} then #{s2.inspect}",
                      "input=#{describe_input(input)} #{ctx}")
        end
      else
        Viol.record(campaign, "roundtrip", "canonical form does not reparse: #{s1.inspect}",
                    "input=#{describe_input(input)} #{ctx}")
      end
    end

    check_regions(input, parsed, shape, campaign: campaign, ctx: ctx)
  end

  # Array-of-lines combining must equal the pre-joined String.
  return unless input.is_a?(Array) && input.all? { |l| l.is_a?(String) && l.ascii_only? }

  joined = input.join(", ")
  SHAPES.each do |shape|
    a_value, a_err = safe { sfv_entry(shape).call(input) }
    b_value, b_err = safe { sfv_entry(shape).call(joined) }
    if a_err.is_a?(Exception) != b_err.is_a?(Exception) ||
       (a_err.is_a?(Exception) && b_err.is_a?(Exception) && a_err.class != b_err.class)
      Viol.record(CAMPAIGN, "combine",
                  "Array input and joined String disagree: #{a_err&.class || :ok} vs #{b_err&.class || :ok}",
                  "input=#{describe_input(input)} #{ctx}")
    elsif a_err.is_a?(Exception) && b_err.is_a?(Exception)
      check_offset("combine", a_err, input, campaign: CAMPAIGN, ctx: ctx)
    elsif a_value && b_value
      unless Eq.top(a_value, b_value, shape)
        Viol.record(CAMPAIGN, "combine", "Array input and joined String parse differently",
                    "input=#{describe_input(input)} #{ctx}")
      end
    end
  end
end

# Regions/parse agreement, span sanity, and member/text correspondence.
def check_regions(input, parsed, shape, campaign: CAMPAIGN, ctx: nil)
  label = "SFV.regions_#{shape_name(shape)}"
  outcome, regions = try(label, [Fast::SFV::ParseError, TypeError], input, campaign: campaign, ctx: ctx) do
    sfv_regions(shape).call(input)
  end
  if outcome != :ok
    Viol.record(campaign, "regions-agreement",
                "parse succeeded but regions raised #{regions.class}: #{regions.message}",
                "input=#{describe_input(input)} #{ctx}")
    return
  end

  combined = regions.combined
  size = combined.bytesize
  members = regions.members
  # A dictionary region per OCCURRENCE (duplicates kept, documented); the
  # parse reduces them last-wins, so the compared count is the reduced one.
  counted = members
  if shape == :dictionary
    counted = {}
    members.each { |m| counted[combined.byteslice(m.key_start, m.key_end - m.key_start)] = m }
  end
  expected_count = shape == :item ? 1 : parsed.size
  if counted.size != expected_count
    Viol.record(campaign, "regions-agreement",
                "region count #{counted.size} != parsed member count #{expected_count}",
                "input=#{describe_input(input)} #{ctx}")
    return
  end

  prev_end = 0
  members.each_with_index do |m, index|
    unless m.start >= prev_end && m.end <= size && m.start <= m.end
      Viol.record(campaign, "regions-span",
                  "member #{index} span #{m.start}..#{m.end} outside #{prev_end}..#{size}",
                  "input=#{describe_input(input)} #{ctx}")
    end
    if m.key_start && !(m.key_start <= m.key_end && m.key_end <= m.value_start && m.value_start <= m.value_end)
      Viol.record(campaign, "regions-span",
                  "member #{index} key/value ordering #{m.key_start},#{m.key_end},#{m.value_start},#{m.value_end}",
                  "input=#{describe_input(input)} #{ctx}")
    end
    param_prev = m.value_end
    m.params.each_with_index do |p, pi|
      unless p.start >= param_prev && p.end <= m.end
        Viol.record(campaign, "regions-span",
                    "member #{index} param #{pi} span #{p.start}..#{p.end} outside #{param_prev}..#{m.end}",
                    "input=#{describe_input(input)} #{ctx}")
      end
      param_prev = p.end
    end
    prev_end = m.end
  end

  if shape == :dictionary
    reduced = {}
    members.each do |m|
      reduced[combined.byteslice(m.key_start, m.key_end - m.key_start)] = m
    end
    unless reduced.keys == parsed.keys
      Viol.record(campaign, "regions-agreement",
                  "reduced region keys #{reduced.keys.inspect} != parsed keys #{parsed.keys.inspect}",
                  "input=#{describe_input(input)} #{ctx}")
    end
  end

  # An Item member's value span must reparse as that bare value in isolation.
  check_member_slice = lambda do |member, region, position|
    next if region.value_start == region.value_end # valueless dictionary form
    next unless member.is_a?(Fast::SFV::Item)

    slice = combined.byteslice(region.value_start, region.value_end - region.value_start)
    o, reparsed = try("SFV.parse_item (member slice)", [Fast::SFV::ParseError], slice,
                      campaign: campaign, ctx: "#{ctx} member-slice-#{position}") do
      sfv_entry(:item).call(slice)
    end
    if o == :ok
      unless Eq.bare(reparsed.value, member.value)
        Viol.record(campaign, "regions-value",
                    "member value slice #{slice.inspect} reparses differently (#{member.value.inspect})",
                    "input=#{describe_input(input)} #{ctx}")
      end
    else
      outcome = o == :doc ? "is not a standalone item" : "raised #{reparsed.class}"
      Viol.record(campaign, "regions-value",
                  "member value slice #{slice.inspect} #{outcome}",
                  "input=#{describe_input(input)} #{ctx}")
    end
  end

  if shape == :item
    check_member_slice.call(parsed, members[0], 0)
  else
    parsed.each_with_index { |m, i| check_member_slice.call(m, members[i], i) }
  end
end

# ---------------------------------------------------------------------------
# Dependent gems
# ---------------------------------------------------------------------------

DEPENDENTS = [
  ["Fast::Priority", Fast::Priority, Fast::Priority::ParseError],
  ["Digest::ContentDigest", Fast::Digest::ContentDigest, Fast::Digest::ParseError],
  ["Digest::ReprDigest", Fast::Digest::ReprDigest, Fast::Digest::ParseError],
  ["Digest::WantContentDigest", Fast::Digest::WantContentDigest, Fast::Digest::ParseError],
  ["Digest::WantReprDigest", Fast::Digest::WantReprDigest, Fast::Digest::ParseError],
  ["ProxyStatus", Fast::ProxyStatus, Fast::ProxyStatus::ParseError],
  ["CacheStatus", Fast::CacheStatus, Fast::CacheStatus::ParseError],
  ["TargetedCacheControl", Fast::TargetedCacheControl, Fast::TargetedCacheControl::ParseError],
  ["ClientCert::Cert", Fast::ClientCert::Cert, Fast::ClientCert::ParseError],
  ["ClientCert::Chain", Fast::ClientCert::Chain, Fast::ClientCert::ParseError]
].freeze

# The gems whose leniency DROPS what strict would reject: their lenient to_s
# must strict-reparse. (Proxy/Cache/TCC preserve offenders in the data
# instead, so that law does not hold for them.)
STRICT_REPARSE = [
  "Fast::Priority", "Digest::ContentDigest", "Digest::ReprDigest",
  "Digest::WantContentDigest", "Digest::WantReprDigest",
  "ClientCert::Cert", "ClientCert::Chain"
].freeze

def check_dependents(input, campaign: CAMPAIGN, ctx: nil)
  DEPENDENTS.each do |name, mod, parse_error|
    check_dependent_full(input, mod, name, parse_error, campaign: campaign, ctx: ctx)
  end
end

def check_dependent_full(input, mod, name, parse_error, campaign: CAMPAIGN, ctx: nil)
  o1, value = try("#{name}.parse", [TypeError], input, campaign: campaign, ctx: ctx) { mod.parse(input) }
  o2, error = try("#{name}.parse!", [parse_error, TypeError], input, campaign: campaign, ctx: ctx) do
    mod.parse!(input)
  end
  check_offset("#{name}.parse!", error, input, campaign: campaign, ctx: ctx) if o2 == :doc && error.is_a?(parse_error)

  o3, v = try("#{name}.valid?", [], input, campaign: campaign, ctx: ctx) { mod.valid?(input) }
  if (o3 == :ok) && (v != (o2 == :ok))
    Viol.record(campaign, "valid-coherence",
                "#{name}.valid? answered #{v.inspect} but parse! #{o2 == :ok ? 'succeeded' : 'raised'}",
                "input=#{describe_input(input)} #{ctx}")
  end

  return unless o1 == :ok && value

  s, err = safe { value.to_s }
  if err
    Viol.record(campaign, "lenient-to_s", "#{name}#to_s raised #{err.class}: #{err.message}",
                "input=#{describe_input(input)} #{ctx}")
    return
  end

  o4, value2 = try("#{name}.parse (of to_s)", [TypeError], s, campaign: campaign, ctx: ctx) { mod.parse(s) }
  if o4 == :ok && value2
    s2, err2 = safe { value2.to_s }
    if err2
      Viol.record(campaign, "lenient-idempotence", "#{name} second to_s raised #{err2.class}",
                  "input=#{describe_input(input)} #{ctx}")
    elsif s2 != s
      Viol.record(campaign, "lenient-idempotence",
                  "#{name}: parse(to_s(parse(x))).to_s #{s2.inspect} != to_s(parse(x)) #{s.inspect}",
                  "input=#{describe_input(input)} #{ctx}")
    end
  end

  return unless STRICT_REPARSE.include?(name)

  o5, error5 = try("#{name}.parse! (of to_s)", [parse_error], s, campaign: campaign, ctx: ctx) do
    mod.parse!(s)
  end
  return unless o5 == :doc && error5

  Viol.record(campaign, "lenient-strict-reparse",
              "#{name}: parse!(to_s(parse(x))) raised #{error5.class}: #{error5.message}",
              "input=#{describe_input(input)} to_s=#{s.inspect} #{ctx}")
end

# ---------------------------------------------------------------------------
# Campaigns
# ---------------------------------------------------------------------------

# Positional: <campaign> [iterations] [seed]. The one flag, --starry-lib <dir>
# (or --starry-lib=<dir>), names the starry peer's directory; ENV["STARRY_LIB"]
# is the flag-less equivalent. STARRY_DIR is resolved before the RNG seeds so
# the starry hookup never touches the random stream.
USAGE = "usage: ruby script/fuzz.rb <campaign> [iterations] [seed] [--starry-lib <dir>]"

starry_dir = nil
positional = []
argv = ARGV.dup
until argv.empty?
  arg = argv.shift
  if arg == "--starry-lib"
    starry_dir = argv.shift
    abort USAGE if starry_dir.nil? || starry_dir.start_with?("--")
  elsif arg.start_with?("--starry-lib=")
    starry_dir = arg.delete_prefix("--starry-lib=")
  elsif arg.start_with?("--")
    abort USAGE
  else
    positional << arg
  end
end
STARRY_DIR = starry_dir || ENV["STARRY_LIB"]
CAMPAIGN = positional[0] || "contract"
ITERATIONS = (positional[1] || 10_000).to_i
SEED = (positional[2] || 20_261_127).to_i
RNG = Random.new(SEED)

HOSTILE_SEEDS = [
  "", " ", "\t", ",", ", ", ";", "=", "(", ")", "(a)", "(a b)", "(a; b)", "(a) ;x=1",
  "?1", "?0", "?2", "?", "@1", "@-1", "@1.5", "@", "%\"a\"", "%\"", "%\"%\"", "%\"%41\"",
  "%\"\\\"", "a=%\"b\\\"c\", d=1", "a;q=1", "a;q", "u=9", "u=8, i=?1", "u=?1",
  "1, 2, 3", "1.5, -1.5, 0.0", "-0", "-0.0", "00", "007", "0.5", ".5", "5.", "1.2345",
  "1234567890123456789", "999999999999999", "-999999999999999", "9999999999999999",
  ":AAAA:", ":AAAA", ":AA:", "::", ":a:", ":/==:", ":\xFF:",
  "\"abc\"", "\"a\\\"b\"", "\"a\\\\b\"", "\"a\\z\"", "\"unterminated", "\"a\nb\"",
  "a=b, a=1", "a=1, a=2", "a, a", "a;a;a=1", "token", "Token", "to-ken", "to:ken", "to/ken",
  "a=b;c=\"x,y\"", "x=%\"\\\", u=9", "sha-256=3, foo=%\"\\\", sha-256=11",
  "a; x=%\"\\\", 5", ":AAAA:, foo=%\"\\\", 5", "5", "\x00", "\x7F", "\xFF\xFE",
  "a=\x00", "u=\x00", "é=1", "a=é", "1".encode("UTF-16LE"), "a".encode("UTF-32BE"),
  %w[a b], ["a", 1], ["a", "b".encode("UTF-16LE")], ["a".b, "b".dup.force_encoding("UTF-16LE")],
  ["a=", "b"], ["", ""], %w[a b c]
].freeze

def seed_texts
  @seed_texts ||= corpus_records.filter_map { |record| record["raw"].join(", ") } + HOSTILE_SEEDS
end

def mutated_input(rng)
  base = seed_texts.sample(random: rng)
  if base.is_a?(Array)
    # A hostile lines-Array seed: mutate each line, keep the odd member.
    return base.map { |l| l.is_a?(String) ? Mut.several(l, rng, rng.rand(2)) : l }
  end

  text = Mut.several(base, rng, 1 + rng.rand(4))
  text = Mut.reencode(text, rng)
  rng.rand(3).zero? ? Mut.to_lines(text, rng) : text
end

def starry_method(shape)
  { item: :parse_item, list: :parse_list, dictionary: :parse_dictionary }[shape]
end

# The differential comparison for one ASCII text: accept/reject and canonical
# form, only when both sides can read the input at all. Skipped (not failed)
# when the starry peer is not configured.
def diff_starry(text, shape, campaign, ctx)
  starry = load_starry
  return if starry.nil?

  s_result, s_err = safe { starry.public_send(starry_method(shape), text) }
  f_result, f_err = safe { sfv_entry(shape).call(text) }
  s_ok = s_err.nil?
  f_ok = f_err.nil?
  if f_ok != s_ok
    # A 9651-only grammar (colon/slash tokens, empty byte sequence) is the
    # peer's blind spot, not a finding: filter by the parsed tree.
    if f_ok && tree_8941?(f_result)
      Viol.record(campaign, "starry-disagree",
                  "impl parses but starry raises: #{text.byteslice(0, 100).inspect}",
                  "#{ctx} starry=#{s_err.class}: #{s_err.message.to_s.byteslice(0, 100)}")
    elsif !f_ok && !text.include?(":") && !text.include?("/")
      Viol.record(campaign, "starry-disagree",
                  "starry parses but impl raises: #{text.byteslice(0, 100).inspect}",
                  "#{ctx} impl=#{f_err.class}: #{f_err.message.to_s.byteslice(0, 100)}")
    end
  elsif f_ok && s_ok
    sc, sc_err = safe { starry.serialize(s_result) }
    fc, fc_err = safe { sfv_serialize(shape).call(f_result) }
    if sc_err || fc_err
      Viol.record(campaign, "starry-disagree",
                  "canonicalization raised: starry=#{sc_err&.class} impl=#{fc_err&.class}",
                  "text=#{text.byteslice(0, 100).inspect} #{ctx}")
    elsif tree_8941?(f_result) && sc != fc
      Viol.record(campaign, "starry-disagree",
                  "canonical forms differ: impl #{fc.inspect} vs starry #{sc.inspect}",
                  "text=#{text.byteslice(0, 100).inspect} #{ctx}")
    end
  end
end

def run_bootstrap
  starry = load_starry
  sfv_ok = 0
  starry_ok = 0
  corpus_records.each do |record|
    raw = record["raw"]
    shape = { "item" => :item, "list" => :list, "dictionary" => :dictionary }[record["header_type"]]
    next unless shape

    if record["must_fail"]
      outcome, error = try("bootstrap parse must_fail", [Fast::SFV::ParseError], raw, campaign: "bootstrap") do
        sfv_entry(shape).call(raw)
      end
      if outcome == :ok
        Viol.record("bootstrap", "corpus", "must_fail record parsed: #{record['name']}", record["file"])
      elsif outcome == :doc && error
        check_offset("bootstrap must_fail", error, raw, campaign: "bootstrap")
      elsif outcome == :bad
        Viol.record("bootstrap", "corpus", "must_fail record raised undocumented class: #{record['name']}",
                    record["file"])
      end
      next
    end

    tree = Tree.top(record["expected"], record["header_type"])
    parsed, err = safe { sfv_entry(shape).call(raw) }
    if err
      Viol.record("bootstrap", "corpus", "valid record does not parse: #{record['name']}", record["file"])
      next
    end
    unless Eq.top(parsed, tree, shape)
      Viol.record("bootstrap", "corpus", "parse != expected: #{record['name']}", record["file"])
    end
    sfv_ok += 1

    impl, impl_err = safe { sfv_serialize(shape).call(parsed) }
    ref = Ref.serialize_top(tree, shape)
    if impl_err || impl != ref
      Viol.record("bootstrap", "ref-serializer",
                  "impl serialized #{impl.inspect} (#{impl_err&.class}) but ref serialized " \
                  "#{ref.inspect}: #{record['name']}",
                  record["file"])
    end

    raw_text = raw.join(", ")
    next if starry.nil?
    next unless raw_text.ascii_only? && tree_8941?(tree)

    s_result, s_err = safe { starry.public_send(starry_method(shape), raw_text) }
    if s_err.nil?
      sc, sc_err = safe { starry.serialize(s_result) }
      if sc_err
        Viol.record("bootstrap", "starry-bootstrap",
                    "starry serialize raised #{sc_err.class}: #{sc_err.message.to_s.byteslice(0, 100)}: " \
                    "#{record['name']}",
                    record["file"])
      elsif sc != impl
        Viol.record("bootstrap", "starry-bootstrap",
                    "starry canonical #{sc.inspect} != impl #{impl.inspect}: #{record['name']}", record["file"])
      end
      starry_ok += 1
    else
      Viol.record("bootstrap", "starry-bootstrap",
                  "starry cannot parse corpus-valid record: #{record['name']}", record["file"])
    end
  end

  puts "bootstrap: #{sfv_ok} parse records checked, #{starry_ok} starry-differenced"
end

def run_contract(iterations, rng)
  iterations.times do |i|
    input = mutated_input(rng)
    ctx = "iter=#{i}"
    check_substrate(input, ctx: ctx)
    check_dependents(input, ctx: ctx)
  end
end

def run_generate(iterations, rng)
  load_starry
  iterations.times do |i|
    shape = SHAPES.sample(random: rng)
    tree = Gen.tree(rng, shape)
    canonical = Ref.serialize_top(tree, shape)
    empty = canonical.nil?
    text = empty ? "" : canonical
    ctx = "iter=#{i} shape=#{shape} generated=#{text.byteslice(0, 120).inspect}"

    outcome, parsed = try("SFV.parse_#{shape_name(shape)} (generated)", [Fast::SFV::ParseError], text,
                          campaign: "generate", ctx: ctx) { sfv_entry(shape).call(text) }
    if outcome == :doc
      Viol.record("generate", "parse-gap", "generated valid input does not parse: #{text.inspect}",
                  "#{ctx} error=#{parsed.message}")
    elsif outcome == :ok
      unless Eq.top(parsed, tree, shape)
        Viol.record("generate", "parse-tree", "parsed tree != generated tree: #{text.inspect}", ctx)
      end
      impl, impl_err = safe { sfv_serialize(shape).call(parsed) }
      expected = empty ? nil : text
      if impl_err || impl != expected
        Viol.record("generate", "canonical-mismatch",
                    "impl serialized #{impl.inspect} (#{impl_err&.class}) but ref serialized #{expected.inspect}",
                    "#{ctx} tree=#{safe { tree.inspect }.first.to_s.byteslice(0, 160)}")
      end
    end

    diff_starry(text, shape, "generate", ctx) if text.ascii_only? && text.encoding != Encoding::ASCII_8BIT &&
                                                 !text.include?("@") && !text.include?("%")

    check_substrate(text, campaign: "generate", ctx: ctx)
    check_dependents(text, campaign: "generate", ctx: ctx)
  end
end

def run_regions(iterations, rng)
  iterations.times do |i|
    input = mutated_input(rng)
    ctx = "iter=#{i}"
    SHAPES.each do |shape|
      outcome, parsed = try("regions-parse", [Fast::SFV::ParseError, TypeError], input,
                            campaign: "regions", ctx: ctx) { sfv_entry(shape).call(input) }
      next unless outcome == :ok

      check_regions(input, parsed, shape, campaign: "regions", ctx: ctx)
    end
  end
end

def run_diff(iterations, rng)
  return :skipped if load_starry.nil?

  iterations.times do |i|
    input = mutated_input(rng)
    text = nil
    if input.is_a?(String)
      text = input
    elsif input.is_a?(Array) && input.all? { |l| l.is_a?(String) }
      joined, jerr = safe { input.join(", ") }
      text = jerr ? nil : joined
    end
    next unless text.is_a?(String) && text.ascii_only? && text.encoding != Encoding::ASCII_8BIT

    shape = SHAPES.sample(random: rng)
    ctx = "iter=#{i} shape=#{shape}"
    next if text.include?("@") || text.include?("%")

    diff_starry(text, shape, "diff", ctx)
  end
end

HOSTILE_VALUES = [
  nil, :sym, "s", 1, 1.5, true, false, [], {}, Object.new, BasicObject.new,
  Rational(1, 2), Float::NAN, Float::INFINITY, 10**20, -10**20, 1.0e30, 1.0e-30,
  "bin".b, "utf8é", "\x00", Fast::SFV::Token.new("tok"), Fast::SFV::Date.new(1),
  Fast::SFV::DisplayString.new("x"), Class.new, proc {}, (1.0..2.0)
].freeze

def hostile(rng)
  HOSTILE_VALUES.sample(random: rng)
end

def describe_tree(tree)
  safe { tree.inspect }.first.to_s.byteslice(0, 200)
end

def mutate_tree(tree, rng)
  case tree
  when Fast::SFV::Item
    if rng.rand(3).zero?
      Fast::SFV::Item.new(hostile(rng), rng.rand(3).zero? ? hostile(rng) : tree.params)
    else
      Fast::SFV::Item.new(mutate_tree(tree.value, rng), tree.params)
    end
  when Fast::SFV::InnerList
    Fast::SFV::InnerList.new(tree.items, rng.rand(4).zero? ? hostile(rng) : tree.params)
  when Array
    rng.rand(5).zero? ? hostile(rng) : tree.map { |m| mutate_tree(m, rng) }
  when Hash
    if rng.rand(5).zero?
      hostile(rng)
    else
      # Keys must stay hashable: Hash#to_h would call #hash on a BasicObject.
      mutated = {}
      tree.each do |k, v|
        key = rng.rand(6).zero? ? [:sym, "k", 5].sample(random: rng) : k
        mutated[key] = mutate_tree(v, rng)
      end
      mutated
    end
  else
    rng.rand(4).zero? ? hostile(rng) : tree
  end
end

def run_emit(iterations, rng)
  iterations.times do |i|
    ctx = "iter=#{i}"
    victim = hostile(rng)

    [[Fast::SFV.method(:serialize_item), "SFV.serialize_item"],
     [Fast::SFV.method(:serialize_list), "SFV.serialize_list"],
     [Fast::SFV.method(:serialize_dict), "SFV.serialize_dict"]].each do |fn, label|
      try(label, [Fast::SFV::SerializeError], victim, campaign: "emit", ctx: ctx) { fn.call(victim) }
    end

    item, = safe { Fast::SFV::Item.new(victim, { "k" => hostile(rng) }) }
    try("Item#to_s", [Fast::SFV::SerializeError], victim, campaign: "emit", ctx: ctx) { item.to_s } if item

    inner, = safe { Fast::SFV::InnerList.new([Fast::SFV::Item.new(1, {}.freeze)], { "k" => hostile(rng) }) }
    try("InnerList#to_s", [Fast::SFV::SerializeError], victim, campaign: "emit", ctx: ctx) { inner.to_s } if inner

    try("Token.new", [ArgumentError, TypeError], victim, campaign: "emit", ctx: ctx) do
      Fast::SFV::Token.new(victim)
    end

    # The emit-never-lies property on a mutated valid tree.
    shape = SHAPES.sample(random: rng)
    tree = Gen.tree(rng, shape)
    mutated_tree = mutate_tree(tree, rng)
    outcome, out = try("serialize (mutated tree)", [Fast::SFV::SerializeError], nil, campaign: "emit", ctx: ctx) do
      sfv_serialize(shape).call(mutated_tree)
    end
    if outcome == :ok && out
      o2, reparsed = try("parse (of emit output)", [Fast::SFV::ParseError], out, campaign: "emit", ctx: ctx) do
        sfv_entry(shape).call(out)
      end
      if o2 == :doc
        Viol.record("emit", "emit-lies",
                    "emit output #{out.inspect} does not reparse (#{reparsed.class}: #{reparsed.message})",
                    "tree-input=#{describe_tree(mutated_tree)} #{ctx}")
      elsif o2 == :ok
        # §4.1.5's decimal rounding is lossy by spec (1e-30 emits "0.0"), so
        # the law is not reparse == tree: the emitted output must be a
        # canonical fixed point, and it must be what the model serializer
        # produces for the same tree.
        ref_reparsed, ref_err = safe { Ref.serialize_top(reparsed, shape) }
        ref_tree, ref_tree_err = safe { Ref.serialize_top(mutated_tree, shape) }
        if ref_err.nil? && ref_reparsed != out
          Viol.record("emit", "emit-lies",
                      "emit output #{out.inspect} is not a canonical fixed point " \
                      "(reparsed serializes as #{ref_reparsed.inspect})",
                      "tree-input=#{describe_tree(mutated_tree)} #{ctx}")
        end
        if ref_tree_err.nil? && ref_tree != out
          Viol.record("emit", "canonical-mismatch",
                      "impl serialized #{out.inspect} but ref serialized #{ref_tree.inspect}",
                      "tree-input=#{describe_tree(mutated_tree)} #{ctx}")
        end
        if ref_tree_err && !ref_tree_err.is_a?(FuzzInternalError)
          # The model serializer rejected the tree; the impl must have too.
          Viol.record("emit", "canonical-mismatch",
                      "ref refuses to serialize this tree (#{ref_tree_err.message.to_s.byteslice(0, 80)}) " \
                      "but impl emitted #{out.inspect}",
                      "tree-input=#{describe_tree(mutated_tree)} #{ctx}")
        end
      end
    end

    try("Priority::Parameters.new", [Fast::Priority::SerializeError], victim, campaign: "emit", ctx: ctx) do
      Fast::Priority::Parameters.new(urgency: victim, incremental: victim, unknown: victim)
    end
    try("Priority::H2.encode_payload", [Fast::Priority::SerializeError], victim, campaign: "emit", ctx: ctx) do
      Fast::Priority::H2.encode_payload(victim, victim)
    end
    try("Priority::H3.encode_payload", [Fast::Priority::SerializeError], victim, campaign: "emit", ctx: ctx) do
      Fast::Priority::H3.encode_payload(victim, victim)
    end
    [Fast::Digest::ContentDigest, Fast::Digest::ReprDigest,
     Fast::Digest::WantContentDigest, Fast::Digest::WantReprDigest].each do |klass|
      try("#{klass.name.split('::').last}.new", [Fast::Digest::SerializeError], victim, campaign: "emit", ctx: ctx) do
        klass.new({ "a" => victim })
      end
    end
    try("ProxyStatus::Hop.new", [Fast::ProxyStatus::SerializeError], victim, campaign: "emit", ctx: ctx) do
      Fast::ProxyStatus::Hop.new(victim, { "k" => victim })
    end
    try("ProxyStatus.append", [Fast::ProxyStatus::SerializeError, TypeError], victim, campaign: "emit", ctx: ctx) do
      Fast::ProxyStatus.append(victim, victim, { "k" => victim })
    end
    try("CacheStatus.append", [Fast::CacheStatus::SerializeError, TypeError], victim, campaign: "emit", ctx: ctx) do
      Fast::CacheStatus.append(victim, victim, { "k" => victim })
    end
    try("TargetedCacheControl.new", [Fast::TargetedCacheControl::SerializeError], victim, campaign: "emit", ctx: ctx) do
      Fast::TargetedCacheControl.new({ "a" => victim })
    end
    try("ClientCert::Cert.new", [Fast::ClientCert::SerializeError], victim, campaign: "emit", ctx: ctx) do
      Fast::ClientCert::Cert.new(victim)
    end
    try("ClientCert::Chain.new", [Fast::ClientCert::SerializeError], victim, campaign: "emit", ctx: ctx) do
      Fast::ClientCert::Chain.new(victim)
    end
    try("ClientCert::Chain#split", [ArgumentError], victim, campaign: "emit", ctx: ctx) do
      Fast::ClientCert::Chain.new([]).split(victim)
    end
    try("ProxyStatus.promote", [TypeError], victim, campaign: "emit", ctx: ctx) do
      Fast::ProxyStatus.promote(victim, hostile(rng))
    end
  end
end

def run_frames(iterations, rng)
  iterations.times do |i|
    ctx = "iter=#{i}"
    size = rng.rand(0..40)
    payload = Array.new(size) { rng.rand(256) }.pack("C*")
    check_frame(Fast::Priority::H2, payload, :stream_id, ctx)
    check_frame(Fast::Priority::H3, payload, :element_id, ctx)

    if rng.rand(2).zero?
      id = rng.rand(1..0x7FFF)
      params = Fast::Priority.parse(Mut.several("u=#{rng.rand(8)}, i=?#{rng.rand(2)}", rng, 2))
      payload, = safe { Fast::Priority::H2.encode_payload(id, params) }
    else
      id = rng.rand(0..(1 << 62))
      payload, = safe { Fast::Priority::H3.encode_payload(id, Fast::Priority.parse("u=3")) }
    end
    next unless payload

    payload = Mut.several(payload, rng, rng.rand(3))
    check_frame(Fast::Priority::H2, payload, :stream_id, ctx)
    check_frame(Fast::Priority::H3, payload, :element_id, ctx)
  end

  # Boundary identifiers and the non-minimal varint forms.
  [0, 1, 0x7FFF_FFFF, (1 << 62) - 1, 1 << 62, -1, 1.5, "5"].each do |id|
    try("H2.encode_payload (boundary)", [Fast::Priority::SerializeError], id, campaign: "frames") do
      Fast::Priority::H2.encode_payload(id, Fast::Priority.parse("u=3"))
    end
    try("H3.encode_payload (boundary)", [Fast::Priority::SerializeError], id, campaign: "frames") do
      Fast::Priority::H3.encode_payload(id, Fast::Priority.parse("u=3"))
    end
  end
  { 1 => "\x41", 0x41 => "\x40\x41", 0x4141 => "\x80\x41\x41",
    0x4041_4141 => "\xC0\x00\x00\x00\x40\x41\x41\x41" }.each do |value, wire|
    o, frame = try("H3.decode_payload (non-minimal varint)", [TypeError, Fast::Priority::ParseError], wire,
                   campaign: "frames") { Fast::Priority::H3.decode_payload(wire) }
    if o == :ok && frame.element_id != value
      Viol.record("frames", "varint", "non-minimal varint decoded #{frame.element_id} != #{value}", wire.unpack1("H*"))
    end
  end
end

def check_frame(codec, payload, id_reader, ctx)
  o, frame = try("#{codec == Fast::Priority::H2 ? 'H2' : 'H3'}.decode_payload",
                 [TypeError, Fast::Priority::ParseError], payload, campaign: "frames", ctx: ctx) do
    codec.decode_payload(payload)
  end
  return unless o == :ok

  id = frame.public_send(id_reader)
  max = codec == Fast::Priority::H2 ? 0x7FFF_FFFF : (1 << 62) - 1
  unless id.is_a?(Integer) && id >= 0 && id <= max
    Viol.record("frames", "frame-id", "#{id_reader}=#{id.inspect} out of range",
                "payload=#{payload.unpack1('H*')} #{ctx}")
  end
  unless frame.field_value.is_a?(String) && frame.field_value.encoding == Encoding::ASCII_8BIT
    Viol.record("frames", "frame-field-value", "field_value #{frame.field_value.inspect} not BINARY",
                "payload=#{payload.unpack1('H*')} #{ctx}")
  end
  unless frame.priority.is_a?(Fast::Priority::Parameters)
    Viol.record("frames", "frame-priority", "priority is #{frame.priority.class}", ctx)
  end
  return unless frame.error

  unless frame.error.is_a?(Fast::Priority::ParseError) && frame.error.offset.is_a?(Integer) &&
         frame.error.offset >= 0 && frame.error.offset <= frame.field_value.bytesize
    Viol.record("frames", "frame-error", "error #{frame.error.class} offset #{frame.error.offset.inspect}",
                "field_value=#{frame.field_value.inspect} #{ctx}")
  end
end

def gen_base64(rng, size)
  [Array.new(size) { rng.rand(256) }.pack("C*")].pack("m0")
end

def gen_pem(rng, der_size)
  base64 = gen_base64(rng, der_size)
  lines = base64.scan(/.{1,64}/)
  "-----BEGIN CERTIFICATE-----\n#{lines.join("\n")}\n-----END CERTIFICATE-----\n"
end

def run_pem(iterations, rng)
  iterations.times do |i|
    ctx = "iter=#{i}"
    pem = gen_pem(rng, rng.rand(1..80))
    blocks = [pem]
    blocks << gen_pem(rng, rng.rand(1..40)) while blocks.size < 3 && rng.rand(2).zero?

    o, field = try("pem_to_field", [Fast::ClientCert::Error, TypeError], pem, campaign: "pem", ctx: ctx) do
      Fast::ClientCert.pem_to_field(pem)
    end
    if o == :ok
      again, err = safe { Fast::ClientCert.field_to_pem(field) }
      if err
        Viol.record("pem", "pem-roundtrip", "round trip raised #{err.class}: #{err.message}",
                    "pem=#{pem.inspect} #{ctx}")
      elsif again != pem
        Viol.record("pem", "pem-roundtrip", "field_to_pem(pem_to_field(x)) != x: #{again.inspect} vs #{pem.inspect}",
                    ctx)
      end
      cert, = safe { Fast::ClientCert::Cert.parse(field) }
      unless cert.is_a?(Fast::ClientCert::Cert)
        Viol.record("pem", "pem-cert", "Cert.parse of a PEM-derived field is #{cert.inspect}",
                    "field=#{field.inspect} #{ctx}")
      end
    end

    o2, chain_field = try("pems_to_field", [Fast::ClientCert::Error, TypeError], blocks, campaign: "pem", ctx: ctx) do
      Fast::ClientCert.pems_to_field(blocks)
    end
    if o2 == :ok
      back, err = safe { Fast::ClientCert.field_to_pems(chain_field) }
      canonical, cerr = safe { blocks.map { |b| Fast::ClientCert.field_to_pem(Fast::ClientCert.pem_to_field(b)) } }
      if err || cerr
        Viol.record("pem", "pems-roundtrip", "round trip raised #{(err || cerr).class}: #{(err || cerr).message}",
                    "field=#{chain_field.inspect} #{ctx}")
      elsif back != canonical
        Viol.record("pem", "pems-roundtrip",
                    "field_to_pems(pems_to_field(x)) != x: #{back.inspect} vs #{canonical.inspect}", ctx)
      end
    end

    m = Mut.several(pem, rng, 1 + rng.rand(3))
    try("pem_to_field (mutated)", [Fast::ClientCert::Error, TypeError], m, campaign: "pem", ctx: ctx) do
      Fast::ClientCert.pem_to_field(m)
    end
    field_m = Mut.several(":#{gen_base64(rng, 16)}:", rng, 2)
    try("field_to_pem (mutated)", [Fast::ClientCert::Error, TypeError], field_m, campaign: "pem", ctx: ctx) do
      Fast::ClientCert.field_to_pem(field_m)
    end
    try("field_to_pems (mutated)", [Fast::ClientCert::Error, TypeError], field_m, campaign: "pem", ctx: ctx) do
      Fast::ClientCert.field_to_pems(field_m)
    end
    try("pems_to_field (mutated)", [Fast::ClientCert::Error, TypeError], nil, campaign: "pem", ctx: ctx) do
      Fast::ClientCert.pems_to_field([m, m])
    end
  end
end

def run_perf
  cases = {
    "100k-member token list" => "#{'a, ' * 50_000}a",
    "1MB single token" => "a" * 1_000_000,
    "500k-escape string" => "\"#{'\\"' * 250_000}\"",
    "100k-member dict" => [Array.new(100_000) { |i| "k#{i}=1" }.join(", "), :dictionary],
    "330k b64 byte sequence" => ":#{'A' * 330_000}:",
    "deep parens" => "(" * 100_000,
    "100k params" => "a#{';q=1' * 100_000}",
    "display string 200k" => "%\"#{'a' * 200_000}\""
  }
  cases.each do |name, input|
    text, shape = input.is_a?(Array) ? input : [input, :list]
    t = Benchmark.realtime { safe { sfv_entry(shape).call(text) } }
    puts format("perf %<name>-28s %<time>8.2fs %<state>s", name: name, time: t, state: t < 2.0 ? "ok" : "SLOW")
    Viol.record("perf", "slow", "#{name}: #{t.round(2)}s", text.bytesize.to_s) if t >= 2.0

    half = text.byteslice(0, text.bytesize / 2)
    t2 = Benchmark.realtime { safe { sfv_entry(shape).call(half) } }
    next unless t2.positive? && t / t2 > 8

    Viol.record("perf", "superlinear", "#{name}: 2x size cost #{(t / t2).round(1)}x", text.bytesize.to_s)
  end

  t = Benchmark.realtime { safe { Fast::ProxyStatus.parse("#{'a, ' * 50_000}a") } }
  puts format("perf %<name>-28s %<time>8.2fs", name: "proxy-status 50k members", time: t)
  Viol.record("perf", "slow", "proxy-status 50k: #{t.round(2)}s", "") if t >= 2.0
end

def run_concurrent
  records = corpus_records.first(200)
  inputs = records.map do |r|
    [{ "item" => :item, "list" => :list, "dictionary" => :dictionary }[r["header_type"]], r["raw"].join(", ")]
  end
  expected = inputs.map { |shape, t| outcome_snapshot(shape, t) }
  errors = Queue.new
  workers = Array.new(4) do
    Thread.new do
      300.times do
        inputs.each do |shape, t|
          _, ea = safe { sfv_entry(shape).call(t) }
          errors << ea if ea && !ea.is_a?(Fast::SFV::ParseError)
          _, eb = safe do
            sfv_serialize(shape).call(sfv_entry(shape).call(t))
          rescue StandardError
            nil
          end
          errors << eb if eb && !eb.is_a?(Fast::SFV::SerializeError)
        end
      end
    end
  end
  workers.each(&:join)
  errors.size.times do
    e = errors.pop
    Viol.record("concurrent", "thread-raise", "#{e.class}: #{e.message}", "")
  end

  results = inputs.map { |shape, t| outcome_snapshot(shape, t) }
  return unless results != expected

  Viol.record("concurrent", "nondeterministic", "results differ across runs", "")
end

# A comparable snapshot of one parse outcome: the value's wire form, or the
# error's class and message (never the exception object, whose backtrace
# differs between runs).
def outcome_snapshot(shape, text)
  value, err = safe { sfv_entry(shape).call(text) }
  return ["error", err.class.name, err.message] if err

  ["ok", safe { sfv_serialize(shape).call(value) }.first.inspect]
end

# ---------------------------------------------------------------------------
# Dispatch
# ---------------------------------------------------------------------------

skipped = case CAMPAIGN
          when "bootstrap" then run_bootstrap
          when "contract" then run_contract(ITERATIONS, RNG)
          when "generate" then run_generate(ITERATIONS, RNG)
          when "regions" then run_regions(ITERATIONS, RNG)
          when "diff" then run_diff(ITERATIONS, RNG)
          when "emit" then run_emit(ITERATIONS, RNG)
          when "frames" then run_frames(ITERATIONS, RNG)
          when "pem" then run_pem(ITERATIONS, RNG)
          when "perf" then run_perf
          when "concurrent" then run_concurrent
          else raise "unknown campaign #{CAMPAIGN}"
          end

if skipped == :skipped
  puts "#{CAMPAIGN}: SKIPPED — the starry peer is not configured; no differential " \
       "checks were run (this is neither a pass nor a failure)"
else
  puts "#{CAMPAIGN}: #{Viol.counts.size} distinct violations, #{Viol.counts.values.sum} total occurrences"
end
