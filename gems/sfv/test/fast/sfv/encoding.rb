# frozen_string_literal: true

require "fast/sfv"

# The two input classes the corpus never modeled. A String whose
# encoding is not ASCII-compatible (UTF-16 and UTF-32): RFC 9651 4.2
# step 1 fails the whole field value, and such a value can spell every
# byte inside the ASCII range ("1" in UTF-16LE is "1\x00"), so the
# offset-finding walk stays bounded — a walk that finds no offending
# byte leaves the value positioned and the grammar rejects it (the
# padding NUL is in no grammar class). And an Array of field lines
# whose encodings cannot combine: RFC 9651 4.2 step 2 joins the lines,
# and a line that cannot join with anything is rejected at its start in
# the combined value, never transcoded. Every pin below is a measured
# behavior.
NON_ASCII_ENCODINGS = %w[UTF-16LE UTF-16BE UTF-32LE UTF-32BE].freeze

# The Array batteries: a non-ASCII-compatible second line, a lone one,
# a second line in UTF-32BE, an ASCII-compatible line carrying a high
# byte (the walk still finds the byte — the error byte-exact with a
# plain ASCII-compatible input), and two mutually incompatible
# ASCII-compatible encodings (a join no plain String#join could make).
INCOMPATIBLE_LINES = ["a".b, "b".dup.force_encoding("UTF-16LE")].freeze
LONE_INCOMPATIBLE_LINE = ["1".encode("UTF-16LE")].freeze
INCOMPATIBLE_DICT_LINES = ["a=1", "b=2".encode("UTF-32BE")].freeze
HIGH_BYTE_LINES = ["a", "b\xE9".dup.force_encoding("ISO-8859-1")].freeze
CONFLICTING_HIGH_BYTE_LINES = ["\xE9".dup.force_encoding("ISO-8859-1"), "\xE9".dup.force_encoding("UTF-8")].freeze

# The no-leak battery: the four non-ASCII-compatible encodings as
# Strings and three Array shapes, through all six entry points.
HOSTILE_INPUTS = (NON_ASCII_ENCODINGS.map { |name| "u=1, i".encode(name) } +
                  [INCOMPATIBLE_LINES, LONE_INCOMPATIBLE_LINE, CONFLICTING_HIGH_BYTE_LINES]).freeze

describe "the encoding boundaries" do
  # The ParseError an entry point raised, or nil — the frozen pins are
  # read off it.
  def error_of(entry, input)
    Fast::SFV.public_send(entry, input)
    nil
  rescue Fast::SFV::ParseError => e
    e
  end

  describe "a non-ASCII-compatible String" do
    it "answers a positioned ParseError through every entry point" do
      NON_ASCII_ENCODINGS.each do |name|
        input = "1".encode(name)
        %i[parse_item parse_list parse_dict].each do |entry|
          error = error_of(entry, input)
          expect(error).to be(:kind_of?, Fast::SFV::ParseError)
          expect(error.offset).to be(:kind_of?, Integer)
          expect(error.offset).to be(:>=, 0)
          expect(error.offset).to be(:<=, input.bytesize)
        end
      end
    end

    it "pins the item messages and offsets" do
      error = error_of(:parse_item, "1".encode("UTF-16LE"))
      expect(error.message).to be(:==, "unexpected content after the value at offset 1")
      expect(error.offset).to be(:==, 1)
      error = error_of(:parse_item, "1".encode("UTF-16BE"))
      expect(error.message).to be(:==, "an item must start with a bare item byte at offset 0")
      expect(error.offset).to be(:==, 0)
      error = error_of(:parse_item, "1".encode("UTF-32LE"))
      expect(error.message).to be(:==, "unexpected content after the value at offset 1")
      expect(error_of(:parse_item, "1".encode("UTF-32BE")).offset).to be(:==, 0)
    end

    it "pins the list, dictionary and ASCII-walk messages" do
      error = error_of(:parse_list, "1".encode("UTF-16LE"))
      expect(error.message).to be(:==, "list members are separated by ',' at offset 2")
      expect(error.offset).to be(:==, 2)
      error = error_of(:parse_dict, "1".encode("UTF-16LE"))
      expect(error.message).to be(:==, "a key must start with a lowercase letter or '*' at offset 0")
      expect(error.offset).to be(:==, 0)
      error = error_of(:parse_item, "é".encode("UTF-16LE"))
      expect(error.message).to be(:==, "the field value must be ASCII at offset 0")
      expect(error.offset).to be(:==, 0)
      expect(error_of(:parse_item, "é".encode("UTF-32BE")).offset).to be(:==, 3)
    end

    it "answers false on every mirror" do
      NON_ASCII_ENCODINGS.each do |name|
        input = "1".encode(name)
        expect(Fast::SFV.valid_item?(input)).to be(:==, false)
        expect(Fast::SFV.valid_list?(input)).to be(:==, false)
        expect(Fast::SFV.valid_dict?(input)).to be(:==, false)
      end
    end
  end

  describe "an Array of lines that cannot combine" do
    it "rejects a non-ASCII-compatible line at its start in the combined value" do
      error = error_of(:parse_list, INCOMPATIBLE_LINES)
      expect(error.message).to be(:==, "a field line must be an ASCII-compatible encoding (got UTF-16LE) at offset 3")
      expect(error.offset).to be(:==, 3)
      error = error_of(:parse_item, LONE_INCOMPATIBLE_LINE)
      expect(error.message).to be(:==, "a field line must be an ASCII-compatible encoding (got UTF-16LE) at offset 0")
      expect(error.offset).to be(:==, 0)
      error = error_of(:parse_dict, INCOMPATIBLE_DICT_LINES)
      expect(error.message).to be(:==, "a field line must be an ASCII-compatible encoding (got UTF-32BE) at offset 5")
      expect(error.offset).to be(:==, 5)
    end

    it "keeps the ASCII-compatible high-byte mixes byte-exact" do
      error = error_of(:parse_list, HIGH_BYTE_LINES)
      expect(error.message).to be(:==, "the field value must be ASCII at offset 4")
      expect(error.offset).to be(:==, 4)
      error = error_of(:parse_list, CONFLICTING_HIGH_BYTE_LINES)
      expect(error.message).to be(:==, "the field value must be ASCII at offset 0")
      expect(error.offset).to be(:==, 0)
    end

    it "answers false on every mirror over the hostile Array battery" do
      [INCOMPATIBLE_LINES, LONE_INCOMPATIBLE_LINE, INCOMPATIBLE_DICT_LINES,
       HIGH_BYTE_LINES, CONFLICTING_HIGH_BYTE_LINES].each do |input|
        expect(Fast::SFV.valid_item?(input)).to be(:==, false)
        expect(Fast::SFV.valid_list?(input)).to be(:==, false)
        expect(Fast::SFV.valid_dict?(input)).to be(:==, false)
      end
    end

    it "answers TypeError ahead of any content check" do
      expect { Fast::SFV.parse_list(["a".dup.force_encoding("UTF-16LE"), 5]) }
        .to raise_exception(::TypeError)
    end
  end

  describe "the no-leak sweep" do
    it "answers only ParseError or TypeError, never a foreign error class" do
      HOSTILE_INPUTS.each do |input|
        %i[parse_item parse_list parse_dict valid_item? valid_list? valid_dict?].each do |entry|
          leaked = nil
          begin
            Fast::SFV.public_send(entry, input)
          rescue Fast::SFV::ParseError, ::TypeError
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
