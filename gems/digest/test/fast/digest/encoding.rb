# frozen_string_literal: true

require "fast/digest"

# The two input classes the field's own vectors never modeled: a String
# whose encoding is not ASCII-compatible (UTF-16 and UTF-32 — RFC 9651
# 4.2 step 1 fails the whole field value, so the Dictionary never
# parses), and an Array of field lines whose encodings cannot combine
# (RFC 9651 4.2 step 2 rejects the line at its start in the combined
# value). The recipient semantics hold on both: the lenient parse
# answers the empty value — the RFC 9651 2.2 whole-field ignore, the
# same answer an absent field gives — the strict parse wraps the
# substrate failure with its message and byte offset preserved, and the
# mirror answers false. Never NoMethodError, never
# Encoding::CompatibilityError. Every pin below is a measured behavior.
DIGEST_NON_ASCII_ENCODINGS = %w[UTF-16LE UTF-16BE UTF-32LE UTF-32BE].freeze
DIGEST_FIELD_CLASSES = [
  Fast::Digest::ContentDigest,
  Fast::Digest::ReprDigest,
  Fast::Digest::WantContentDigest,
  Fast::Digest::WantReprDigest
].freeze
DIGEST_MIXED_LINES = ["sha-256=:AAAA:", "md5=:AAAA:".dup.force_encoding("UTF-16LE")].freeze

describe Fast::Digest do
  # The ParseError a strict parse raised, or nil — the frozen offset
  # pins are read off it.
  def strict_error_of(field, input)
    field.parse!(input)
    nil
  rescue Fast::Digest::ParseError => e
    e
  end

  describe ".parse" do
    it "answers the empty value for every non-ASCII-compatible encoding" do
      DIGEST_FIELD_CLASSES.each do |field|
        DIGEST_NON_ASCII_ENCODINGS.each do |name|
          value = field.parse("1".encode(name))
          expect(value.empty?).to be(:==, true)
          expect(value.to_s).to be(:==, "")
        end
      end
    end

    it "answers the empty value for lines that cannot combine" do
      DIGEST_FIELD_CLASSES.each do |field|
        value = field.parse(DIGEST_MIXED_LINES)
        expect(value.empty?).to be(:==, true)
        expect(value.to_s).to be(:==, "")
      end
    end
  end

  describe ".parse!" do
    it "wraps the Dictionary failure with its message and offset" do
      DIGEST_FIELD_CLASSES.each do |field|
        error = strict_error_of(field, "1".encode("UTF-16LE"))
        expect(error).to be(:kind_of?, Fast::Digest::ParseError)
        expect(error.offset).to be(:==, 0)
      end
    end

    it "wraps the line rejection at the line's start in the combined value" do
      DIGEST_FIELD_CLASSES.each do |field|
        error = strict_error_of(field, DIGEST_MIXED_LINES)
        expect(error.offset).to be(:==, 16)
      end
    end
  end

  describe ".valid?" do
    it "answers false on both input classes" do
      DIGEST_FIELD_CLASSES.each do |field|
        DIGEST_NON_ASCII_ENCODINGS.each do |name|
          expect(field.valid?("1".encode(name))).to be(:==, false)
        end
        expect(field.valid?(DIGEST_MIXED_LINES)).to be(:==, false)
      end
    end
  end

  describe "the no-leak sweep" do
    it "answers only its own ParseError or TypeError" do
      hostile = DIGEST_NON_ASCII_ENCODINGS.map { |name| "sha-256=:AAAA:".encode(name) } + [DIGEST_MIXED_LINES]
      DIGEST_FIELD_CLASSES.each do |field|
        hostile.each do |input|
          %i[parse parse! valid?].each do |entry|
            leaked = nil
            begin
              field.public_send(entry, input)
            rescue Fast::Digest::ParseError, ::TypeError
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
