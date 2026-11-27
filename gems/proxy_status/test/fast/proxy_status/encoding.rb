# frozen_string_literal: true

require "fast/proxy_status"

# The two input classes the field's own vectors never modeled: a String
# whose encoding is not ASCII-compatible (UTF-16 and UTF-32 — RFC 9651
# 4.2 step 1 fails the whole field value, so neither the List nor the
# Dictionary ever parses), and an Array of field lines whose encodings
# cannot combine (RFC 9651 4.2 step 2 rejects the line at its start in
# the combined value). The recipient semantics hold on both, for the
# two List fields and the 9213 Dictionary field alike: the lenient
# parse answers the empty value — the RFC 9651 2.2 whole-field ignore,
# the same answer an absent field gives — the strict parse wraps the
# substrate failure with its message and byte offset preserved, and the
# mirror answers false. Never NoMethodError, never
# Encoding::CompatibilityError. Every pin below is a measured behavior.
PROXY_STATUS_NON_ASCII_ENCODINGS = %w[UTF-16LE UTF-16BE UTF-32LE UTF-32BE].freeze
PROXY_STATUS_FIELD_CLASSES = [
  Fast::ProxyStatus,
  Fast::CacheStatus,
  Fast::TargetedCacheControl
].freeze
PROXY_STATUS_MIXED_LINES = ["a=1", "b".dup.force_encoding("UTF-16LE")].freeze

describe "the encoding boundaries" do
  # The ParseError a strict parse raised, or nil — the frozen offset
  # pins are read off it. Each field raises its own class.
  def strict_error_of(field, input)
    field.parse!(input)
    nil
  rescue field::ParseError => e
    e
  end

  describe ".parse" do
    it "answers the empty value for every non-ASCII-compatible encoding" do
      PROXY_STATUS_FIELD_CLASSES.each do |field|
        PROXY_STATUS_NON_ASCII_ENCODINGS.each do |name|
          value = field.parse("1".encode(name))
          expect(value.empty?).to be(:==, true)
          expect(value.to_s).to be(:==, "")
        end
      end
    end

    it "answers the empty value for lines that cannot combine" do
      PROXY_STATUS_FIELD_CLASSES.each do |field|
        value = field.parse(PROXY_STATUS_MIXED_LINES)
        expect(value.empty?).to be(:==, true)
        expect(value.to_s).to be(:==, "")
      end
    end
  end

  describe ".parse!" do
    it "wraps the List failure for the list fields and the key failure for the dictionary field" do
      error = strict_error_of(Fast::ProxyStatus, "1".encode("UTF-16LE"))
      expect(error).to be(:kind_of?, Fast::ProxyStatus::ParseError)
      expect(error.offset).to be(:==, 2)
      error = strict_error_of(Fast::CacheStatus, "1".encode("UTF-16LE"))
      expect(error).to be(:kind_of?, Fast::CacheStatus::ParseError)
      expect(error.offset).to be(:==, 2)
      error = strict_error_of(Fast::TargetedCacheControl, "1".encode("UTF-16LE"))
      expect(error).to be(:kind_of?, Fast::TargetedCacheControl::ParseError)
      expect(error.offset).to be(:==, 0)
    end

    it "wraps the line rejection at the line's start in the combined value" do
      PROXY_STATUS_FIELD_CLASSES.each do |field|
        error = strict_error_of(field, PROXY_STATUS_MIXED_LINES)
        expect(error.offset).to be(:==, 5)
      end
    end
  end

  describe ".valid?" do
    it "answers false on both input classes" do
      PROXY_STATUS_FIELD_CLASSES.each do |field|
        PROXY_STATUS_NON_ASCII_ENCODINGS.each do |name|
          expect(field.valid?("1".encode(name))).to be(:==, false)
        end
        expect(field.valid?(PROXY_STATUS_MIXED_LINES)).to be(:==, false)
      end
    end
  end

  describe "the no-leak sweep" do
    it "answers only its own ParseError or TypeError" do
      hostile = PROXY_STATUS_NON_ASCII_ENCODINGS.map { |name| "a=1, i".encode(name) } + [PROXY_STATUS_MIXED_LINES]
      PROXY_STATUS_FIELD_CLASSES.each do |field|
        hostile.each do |input|
          %i[parse parse! valid?].each do |entry|
            leaked = nil
            begin
              field.public_send(entry, input)
            rescue field::ParseError, ::TypeError
              nil
            rescue StandardError => e
              leaked = e
            end
            expect(leaked).to be(:==, nil)
          end
        end
      end
    end
  end
end
