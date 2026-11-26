# frozen_string_literal: true

require "json"
require "fast/sfv"

# The httpwg structured-field-tests corpus, vendored byte-frozen under
# gems/sfv/test/corpus/ (PROVENANCE.md names the source repository and the
# cloned commit, LICENSE.md its terms). Only the 20 root parse JSONs load
# here — serialisation-tests/ is loaded by serialisation.rb and
# schema/ stays inert. The corpus is read-only to this harness.
CORPUS_FILES = Dir.glob(File.expand_path("../../corpus/*.json", __dir__)).sort
CORPUS = CORPUS_FILES.to_h { |path| [File.basename(path, ".json"), JSON.parse(File.read(path))] }
CORPUS_RECORDS = CORPUS.values.flatten

# RFC 4648 §6 base32, the corpus's encoding for byte sequences — stdlib
# ships no base32, so the expected values are decoded by a hand-rolled
# helper below.
BASE32_ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567"
BASE32_VALUES = Array.new(256, nil).tap do |values|
  BASE32_ALPHABET.each_byte.with_index { |byte, index| values[byte] = index }
end

# A sus predicate for the must_fail records: the raised ParseError's
# #offset must be an Integer byte position inside the combined input — the
# record's raw lines joined with ", ".
class OffsetWithin
  def initialize(size)
    @size = size
  end

  def call(assertions, error)
    offset = error.offset
    assertions.assert(offset.is_a?(Integer) && offset >= 0 && offset <= @size)
  end

  def print(output)
    output.write("offset is an Integer in 0..#{@size}")
  end
end

describe "the httpwg structured-field-tests corpus" do
  it "loads the 20 root parse files and pins the record count at 1607" do
    expect(CORPUS_FILES.size).to be(:==, 20)
    expect(CORPUS_RECORDS.size).to be(:==, 1607)
  end

  # Decodes the corpus's base32 binary values: the RFC 4648 §6 alphabet
  # with "=" padding, the leftover bits dropped.
  def decode_base32(text)
    bytes = String.new(encoding: Encoding::ASCII_8BIT)
    buffer = 0
    bits = 0
    text.each_byte do |byte|
      break if byte == 0x3D

      value = BASE32_VALUES[byte]
      raise "not base32: #{text.inspect}" unless value

      buffer = (buffer << 5) | value
      bits += 5
      if bits >= 8
        bits -= 8
        bytes << ((buffer >> bits) & 0xFF)
      end
    end
    bytes
  end

  # The frozen translation of the corpus's expected structures onto the
  # parser's Ruby side: tokens to Fast::SFV::Token (the class is the tag —
  # content equality alone cannot tell a token from the plain String a
  # quoted string parses to), base32 binaries to their decoded bytes,
  # dates and display strings through #value, parameters and
  # dictionaries as ordered pair lists.

  def matches?(parsed, expected, header_type)
    case header_type
    when "item"
      matches_member?(parsed, expected)
    when "list"
      return false unless parsed.size == expected.size

      parsed.zip(expected).all? { |member, expected_member| matches_member?(member, expected_member) }
    when "dictionary"
      return false unless parsed.size == expected.size

      parsed.to_a.zip(expected).all? do |(key, member), (expected_key, expected_member)|
        key == expected_key && matches_member?(member, expected_member)
      end
    end
  end

  def matches_member?(member, expected)
    if member.is_a?(Fast::SFV::InnerList)
      matches_inner_list?(member, expected)
    else
      matches_item?(member, expected)
    end
  end

  def matches_item?(item, expected)
    matches_bare?(item.value, expected[0]) && matches_params?(item.params, expected[1])
  end

  def matches_inner_list?(inner_list, expected)
    return false unless inner_list.items.size == expected[0].size

    inner_list.items.zip(expected[0]).all? { |item, expected_item| matches_item?(item, expected_item) } &&
      matches_params?(inner_list.params, expected[1])
  end

  def matches_params?(params, expected)
    return false unless params.size == expected.size

    params.to_a.zip(expected).all? do |(key, value), (expected_key, expected_value)|
      key == expected_key && matches_bare?(value, expected_value)
    end
  end

  def matches_bare?(value, expected)
    case expected
    when Hash
      case expected["__type"]
      when "token" then value.is_a?(Fast::SFV::Token) && value == expected["value"]
      when "binary" then value == decode_base32(expected["value"])
      when "date" then value.is_a?(Fast::SFV::Date) && value.value == expected["value"]
      when "displaystring" then value.is_a?(Fast::SFV::DisplayString) && value.value == expected["value"]
      else false
      end
    else
      !value.is_a?(Fast::SFV::Token) && value == expected
    end
  end

  # One entry point per record, on the header_type the record names, with
  # raw (the Array of field lines) as the input — the corpus itself
  # exercises the ", " combining.
  def parse_record(record)
    case record["header_type"]
    when "item" then Fast::SFV.parse_item(record["raw"])
    when "list" then Fast::SFV.parse_list(record["raw"])
    when "dictionary" then Fast::SFV.parse_dict(record["raw"])
    end
  end

  CORPUS.each do |file_name, records|
    describe file_name do
      records.each do |record|
        it record["name"] do
          if record["must_fail"]
            size = record["raw"].join(", ").bytesize
            expect { parse_record(record) }.to raise_exception(Fast::SFV::ParseError).and(OffsetWithin.new(size))
          else
            parsed = begin
              parse_record(record)
            rescue Fast::SFV::ParseError
              nil
            end
            if parsed
              expect(matches?(parsed, record["expected"], record["header_type"])).to be(:==, true)
            else
              # A raise is only acceptable where the corpus marked it
              # can_fail (the RFC's SHOULD-level leniency).
              expect(record["can_fail"]).to be(:==, true)
            end
          end
        end
      end
    end
  end
end
