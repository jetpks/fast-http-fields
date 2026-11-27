# frozen_string_literal: true

require "json"
require "fast/sfv"

# The serialize side of the httpwg structured-field-tests corpus, vendored
# byte-frozen under gems/sfv/test/corpus/ (corpus.rb owns the parse side
# and stays byte-stable). Two parts, one `it` per record: Part B loads
# the four serialisation-tests files and constructs each record's
# `expected` value tree — a must_fail record cannot be serialized, the
# others must canonicalize; Part A round-trips every non-must_fail parse
# record through the matching serialize entry point. The corpus is
# read-only to this harness. The 125 token-generated must_fail records
# carry token values that fail the token grammar itself, so their value
# trees cannot be built: Token.new's ArgumentError satisfies "the value
# cannot be serialised" (the corpus README) at the boundary — see the
# routing in the record `it` below.
SERIALISATION_TESTS = Dir.glob(File.expand_path("../../corpus/serialisation-tests/*.json", __dir__)).sort
SERIALISATION = SERIALISATION_TESTS.to_h { |path| [File.basename(path, ".json"), JSON.parse(File.read(path))] }
SERIALISATION_RECORDS = SERIALISATION.values.flatten
ROUND_TRIP_TESTS = Dir.glob(File.expand_path("../../corpus/*.json", __dir__)).sort
ROUND_TRIPS = ROUND_TRIP_TESTS.to_h { |path| [File.basename(path, ".json"), JSON.parse(File.read(path))] }
ROUND_TRIP_RECORDS = ROUND_TRIPS.values.flatten.reject { |record| record["must_fail"] }

# A sus predicate for the must_fail records: the raised SerializeError's
# #offset must be an Integer byte position into the output built so far —
# non-negative, per the contract's shape.
class SerializeErrorOffset
  def call(assertions, error)
    offset = error.offset
    assertions.assert(offset.is_a?(Integer) && offset >= 0)
  end

  def print(output)
    output.write("offset is a non-negative Integer")
  end
end

# Part B's value tree from the JSON `expected` structure: bare numbers to
# Integer/Float, strings to String (an sf-string), booleans to the
# booleans, a token __type to Fast::SFV::Token through its validating
# constructor — the only __type the serialisation-tests files carry —
# parameters and dictionaries as ordered Hashes.
def build_value(expected, header_type)
  case header_type
  when "item"
    build_member(expected)
  when "list"
    expected.map { |member| build_member(member) }
  when "dictionary"
    expected.to_h { |key, member| [key, build_member(member)] }
  end
end

# One member — [value, parameters]: a bare item, or an inner list when
# the value is the array of its item pairs.
def build_member(expected)
  value = expected[0]
  params = build_params(expected[1])
  if value.is_a?(Array)
    items = value.map { |item| Fast::SFV::Item.new(build_bare(item[0]), build_params(item[1])) }
    Fast::SFV::InnerList.new(items, params)
  else
    Fast::SFV::Item.new(build_bare(value), params)
  end
end

# Parameters: the record's pair array, in order.
def build_params(pairs)
  pairs.empty? ? {} : pairs.to_h { |key, value| [key, build_bare(value)] }
end

# One bare value; the __type object is a token, built through the
# validating Fast::SFV::Token constructor.
def build_bare(expected)
  expected.is_a?(Hash) ? Fast::SFV::Token.new(expected["value"]) : expected
end

def serialize_record(value, header_type)
  case header_type
  when "item" then Fast::SFV.serialize_item(value)
  when "list" then Fast::SFV.serialize_list(value)
  when "dictionary" then Fast::SFV.serialize_dict(value)
  end
end

def parse_record(record)
  case record["header_type"]
  when "item" then Fast::SFV.parse_item(record["raw"])
  when "list" then Fast::SFV.parse_list(record["raw"])
  when "dictionary" then Fast::SFV.parse_dict(record["raw"])
  end
end

describe "the httpwg serialisation-tests corpus" do
  it "loads the 4 serialisation-test files and pins the record count at 553" do
    expect(SERIALISATION_TESTS.size).to be(:==, 4)
    expect(SERIALISATION_RECORDS.size).to be(:==, 553)
  end

  it "pins the round-trip candidates at 734 (1607 parse records minus 873 must_fail)" do
    expect(ROUND_TRIP_RECORDS.size).to be(:==, 734)
  end

  SERIALISATION.each do |file_name, records|
    describe file_name do
      records.each do |record|
        it record["name"] do
          if record["must_fail"]
            # All 125 token-generated records carry token values that are
            # invalid tokens by construction (control bytes, invalid first
            # bytes, spaces, the empty string), so their value trees
            # cannot be built: the corpus README's must_fail wording is
            # "the value cannot be serialised", and an unconstructable
            # value cannot exist — the ArgumentError from Fast::SFV::Token
            # satisfies the record at the boundary. The remaining 418
            # must_fail records build fine and assert the serializer's
            # SerializeError below.
            value = begin
              build_value(record["expected"], record["header_type"])
            rescue ArgumentError
              nil
            end
            if value
              expect { serialize_record(value, record["header_type"]) }
                .to raise_exception(Fast::SFV::SerializeError).and(SerializeErrorOffset.new)
            end
          else
            value = build_value(record["expected"], record["header_type"])
            expect(serialize_record(value, record["header_type"])).to be(:==, record["canonical"][0])
          end
        end
      end
    end
  end
end

describe "the httpwg round-trip corpus" do
  ROUND_TRIPS.each do |file_name, records|
    describe file_name do
      records.reject { |record| record["must_fail"] }.each do |record|
        it record["name"] do
          parsed = begin
            parse_record(record)
          rescue Fast::SFV::ParseError
            nil
          end
          if parsed
            # The expected wire: the canonical form when the record pins
            # one, its raw lines otherwise; the empty array is the
            # omitted field, which the serializer answers with nil.
            wire = record["canonical"] || record["raw"]
            if wire.empty?
              expect(serialize_record(parsed, record["header_type"])).to be(:nil?)
            else
              expect(serialize_record(parsed, record["header_type"])).to be(:==, wire[0])
            end
          else
            expect(record["can_fail"]).to be(:==, true)
          end
        end
      end
    end
  end
end

describe Fast::SFV do
  describe ".serialize_item" do
    it "emits each of the eight bare item types in its canonical wire form" do
      expect(Fast::SFV.serialize_item(Fast::SFV::Item.new(42, {}))).to be(:==, "42")
      expect(Fast::SFV.serialize_item(Fast::SFV::Item.new(-1.23, {}))).to be(:==, "-1.23")
      expect(Fast::SFV.serialize_item(Fast::SFV::Item.new("foo", {}))).to be(:==, "\"foo\"")
      expect(Fast::SFV.serialize_item(Fast::SFV::Item.new(Fast::SFV::Token.new("sugar"), {}))).to be(:==, "sugar")
      expect(Fast::SFV.serialize_item(Fast::SFV::Item.new(true, {}))).to be(:==, "?1")
      expect(Fast::SFV.serialize_item(Fast::SFV::Item.new(false, {}))).to be(:==, "?0")
      expect(Fast::SFV.serialize_item(Fast::SFV::Item.new("hello".b, {}))).to be(:==, ":aGVsbG8=:")
      date = Fast::SFV::Item.new(Fast::SFV::Date.new(1_659_578_233), {})
      expect(Fast::SFV.serialize_item(date)).to be(:==, "@1659578233")
      display = Fast::SFV::DisplayString.new("fü")
      expect(Fast::SFV.serialize_item(Fast::SFV::Item.new(display, {}))).to be(:==, "%\"f%c3%bc\"")
    end

    it "answers a fresh, mutable US-ASCII String the caller owns" do
      output = Fast::SFV.serialize_item(Fast::SFV::Item.new(1, {}))
      expect(output.encoding).to be(:==, Encoding::US_ASCII)
      expect(output.frozen?).to be(:==, false)
      expect(Fast::SFV.serialize_item(Fast::SFV::Item.new(1, {})).equal?(output)).to be(:==, false)
    end

    it "raises SerializeError, never TypeError, for every non-serializable input" do
      probes = [
        42, nil, "42", :sym, [Fast::SFV::Item.new(1, {})],
        Fast::SFV::Item.new(nil, {}),
        Fast::SFV::Item.new(Object.new, {}),
        Fast::SFV::Item.new(10**15, {}),
        Fast::SFV::Item.new(Float::NAN, {}),
        Fast::SFV::Item.new(1, nil),
        Fast::SFV::Item.new(1, :a)
      ]
      probes.each do |probe|
        expect { Fast::SFV.serialize_item(probe) }.to raise_exception(Fast::SFV::SerializeError)
      end
    end

    it "positions the failure: #offset is an Integer byte offset into the output built so far" do
      error = nil
      begin
        Fast::SFV.serialize_list([Fast::SFV::Item.new(1, {}), 42])
      rescue Fast::SFV::SerializeError => e
        error = e
      end
      expect(error).to be(:kind_of?, Fast::SFV::SerializeError)
      expect(error.offset).to be(:kind_of?, Integer)
      expect(error.offset).to be(:>=, 0)
    end

    it "agrees with to_s on the wrappers" do
      item = Fast::SFV.parse_item("2; a=1")
      expect(Fast::SFV.serialize_item(item)).to be(:==, item.to_s)
      inner = Fast::SFV.parse_list("(1 2);a=1")[0]
      expect(inner.to_s).to be(:==, "(1 2);a=1")
      expect(Fast::SFV::Date.new(0).to_s).to be(:==, "@0")
      expect(Fast::SFV::DisplayString.new("foo, bar").to_s).to be(:==, "%\"foo, bar\"")
    end

    it "never infers the wire type from content: the Ruby type is the tag" do
      expect(Fast::SFV.serialize_item(Fast::SFV::Item.new("foo", {}))).to be(:==, "\"foo\"")
      expect(Fast::SFV.serialize_item(Fast::SFV::Item.new(Fast::SFV::Token.new("foo"), {}))).to be(:==, "foo")
      expect(Fast::SFV.serialize_item(Fast::SFV::Item.new("hello", {}))).to be(:==, "\"hello\"")
      expect(Fast::SFV.serialize_item(Fast::SFV::Item.new("hello".b, {}))).to be(:==, ":aGVsbG8=:")
    end

    it "raises SerializeError, positioned, for a Symbol bare value — wrong-typed input now that tokens are Tokens" do
      error = nil
      begin
        Fast::SFV.serialize_item(Fast::SFV::Item.new(:foo, {}))
      rescue Fast::SFV::SerializeError => e
        error = e
      end
      expect(error).to be(:kind_of?, Fast::SFV::SerializeError)
      expect(error.offset).to be(:kind_of?, Integer)
      expect(error.offset).to be(:>=, 0)
    end

    it "rounds the decimal digits as written, ties to even (corpus number.json)" do
      expect(Fast::SFV.serialize_item(Fast::SFV::Item.new(1.0, {}))).to be(:==, "1.0")
      expect(Fast::SFV.serialize_item(Fast::SFV::Item.new(1.2, {}))).to be(:==, "1.2")
      expect(Fast::SFV.serialize_item(Fast::SFV::Item.new(0.5015, {}))).to be(:==, "0.502")
      expect(Fast::SFV.serialize_item(Fast::SFV::Item.new(2.0005, {}))).to be(:==, "2.0")
      expect(Fast::SFV.serialize_item(Fast::SFV::Item.new(9.9995, {}))).to be(:==, "10.0")
    end

    it "serializes negative zero without the sign (4.1.5 step 5: only a value less than 0 carries one)" do
      expect(Fast::SFV.serialize_item(Fast::SFV::Item.new(-0.0, {}))).to be(:==, "0.0")
      reparsed = Fast::SFV.parse_item(Fast::SFV.serialize_item(Fast::SFV::Item.new(-0.0, {})))
      expect(reparsed.value).to be(:==, 0.0)
    end
  end

  describe ".serialize_list" do
    it "omits an empty List or Dictionary from the field entirely" do
      expect(Fast::SFV.serialize_list([])).to be(:nil?)
      expect(Fast::SFV.serialize_dict({})).to be(:nil?)
    end

    it "raises SerializeError for unwrapped members, Symbol keys and wrong containers" do
      expect { Fast::SFV.serialize_list([42]) }.to raise_exception(Fast::SFV::SerializeError)
      expect { Fast::SFV.serialize_list("1, 2") }.to raise_exception(Fast::SFV::SerializeError)
      expect { Fast::SFV.serialize_list([Fast::SFV::InnerList.new([42], {})]) }.to raise_exception(Fast::SFV::SerializeError)
      expect { Fast::SFV.serialize_dict({ "a" => 1 }) }.to raise_exception(Fast::SFV::SerializeError)
      expect { Fast::SFV.serialize_dict({ a: Fast::SFV::Item.new(1, {}) }) }.to raise_exception(Fast::SFV::SerializeError)
      expect { Fast::SFV.serialize_dict([["a", Fast::SFV::Item.new(1, {})]]) }.to raise_exception(Fast::SFV::SerializeError)
      expect { Fast::SFV.serialize_item(Fast::SFV::Item.new(1, { a: true })) }.to raise_exception(Fast::SFV::SerializeError)
    end

    it "serializes the quoted §4.1 vector forms" do
      inner = Fast::SFV::InnerList.new([Fast::SFV::Item.new(1, {}), Fast::SFV::Item.new(2, {})], { "a" => 1 })
      expect(Fast::SFV.serialize_list([inner])).to be(:==, "(1 2);a=1")
      expect(Fast::SFV.serialize_list([Fast::SFV::InnerList.new([], {})])).to be(:==, "()")
      expect(Fast::SFV.serialize_list([Fast::SFV::Item.new(1, {}), Fast::SFV::Item.new(42, {})])).to be(:==, "1, 42")
      item = Fast::SFV::Item.new(5, { "foo" => Fast::SFV::Token.new("bar"), "a" => 1, "b" => false, "c" => true })
      expect(Fast::SFV.serialize_item(item)).to be(:==, "5;foo=bar;a=1;b=?0;c")
      dictionary = {
        "a" => Fast::SFV::Item.new(false, {}),
        "b" => Fast::SFV::Item.new(true, {}),
        "c" => Fast::SFV::Item.new(true, { "foo" => Fast::SFV::Token.new("bar") })
      }
      expect(Fast::SFV.serialize_dict(dictionary)).to be(:==, "a=?0, b, c;foo=bar")
      inner_value = Fast::SFV::InnerList.new([Fast::SFV::Item.new(1, {}), Fast::SFV::Item.new(2, {})], {})
      expect(Fast::SFV.serialize_dict({ "a" => inner_value })).to be(:==, "a=(1 2)")
    end
  end

  describe "the error hierarchy" do
    it "roots SerializeError at Fast::SFV::Error under StandardError" do
      expect(Fast::SFV::SerializeError.ancestors).to be(:include?, Fast::SFV::Error)
      expect(Fast::SFV::SerializeError.ancestors).to be(:include?, StandardError)
    end
  end
end
