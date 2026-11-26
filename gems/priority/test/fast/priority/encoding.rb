# frozen_string_literal: true

require "fast/priority"

# The two input classes the field's own vectors never modeled: a String
# whose encoding is not ASCII-compatible (UTF-16 and UTF-32 — RFC 9651
# 4.2 step 1 fails the whole field value, so the Dictionary never
# parses), and an Array of field lines whose encodings cannot combine
# (RFC 9651 4.2 step 2 rejects the line at its start in the combined
# value). The recipient semantics hold on both: the lenient parse
# answers the RFC 9218 4 defaults, the strict parse wraps the substrate
# failure with its message and byte offset preserved, and the mirror
# answers false. Never NoMethodError, never
# Encoding::CompatibilityError. Every pin below is a measured behavior.
PRIORITY_NON_ASCII_ENCODINGS = %w[UTF-16LE UTF-16BE UTF-32LE UTF-32BE].freeze
PRIORITY_MIXED_LINES = ["a=1", "b".dup.force_encoding("UTF-16LE")].freeze

# The no-leak battery: the four non-ASCII-compatible encodings as
# Strings and the Array mix, through all three entry points.
PRIORITY_HOSTILE_INPUTS = (PRIORITY_NON_ASCII_ENCODINGS.map { |name| "u=1, i".encode(name) } +
                           [PRIORITY_MIXED_LINES]).freeze

describe Fast::Priority do
  # The ParseError a strict parse raised, or nil — the frozen offset
  # pins are read off it.
  def strict_error_of(input)
    Fast::Priority.parse!(input)
    nil
  rescue Fast::Priority::ParseError => e
    e
  end

  describe ".parse" do
    it "answers the RFC 9218 4 defaults for every non-ASCII-compatible encoding" do
      PRIORITY_NON_ASCII_ENCODINGS.each do |name|
        priority = Fast::Priority.parse("1".encode(name))
        expect(priority.urgency).to be(:==, 3)
        expect(priority.incremental).to be(:==, false)
        expect(priority.to_s).to be(:==, "")
        expect(priority.members).to be(:empty?)
      end
    end

    it "answers the RFC 9218 4 defaults for lines that cannot combine" do
      priority = Fast::Priority.parse(PRIORITY_MIXED_LINES)
      expect(priority.urgency).to be(:==, 3)
      expect(priority.incremental).to be(:==, false)
      expect(priority.to_s).to be(:==, "")
      expect(priority.members).to be(:empty?)
    end
  end

  describe ".parse!" do
    it "wraps the Dictionary failure with its message and offset" do
      error = strict_error_of("1".encode("UTF-16LE"))
      expect(error).to be(:kind_of?, Fast::Priority::ParseError)
      expect(error.offset).to be(:==, 0)
      expect(error.message).to be(:include?, "a key must start with a lowercase letter")
    end

    it "wraps the line rejection at the line's start in the combined value" do
      error = strict_error_of(PRIORITY_MIXED_LINES)
      expect(error.offset).to be(:==, 5)
      expect(error.message).to be(:include?, "(got UTF-16LE)")
    end
  end

  describe ".valid?" do
    it "answers false on both input classes" do
      PRIORITY_NON_ASCII_ENCODINGS.each do |name|
        expect(Fast::Priority.valid?("1".encode(name))).to be(:==, false)
      end
      expect(Fast::Priority.valid?(PRIORITY_MIXED_LINES)).to be(:==, false)
    end
  end

  describe "the no-leak sweep" do
    it "answers only its own ParseError or TypeError" do
      PRIORITY_HOSTILE_INPUTS.each do |input|
        %i[parse parse! valid?].each do |entry|
          leaked = nil
          begin
            Fast::Priority.public_send(entry, input)
          rescue Fast::Priority::ParseError, ::TypeError
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
