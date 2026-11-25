# frozen_string_literal: true

require "fast/sfv"

# Allocation budgets for the three parse entry points: what one operation
# costs in Ruby objects beyond the input. Counts are GC.stat, averaged over
# runs so a one-off allocation outside the block (GC.stat's own, under
# coverage) does not count, and everything a measured block touches is a
# local. Measured on Ruby 4.0.10, then frozen: a bare item 2, an item with
# parameters 7, a string item 3, a byte sequence item 3, a display string
# item 4, a three-token list 8, a multi-line list 5, a mixed dictionary
# with an inner list 11.
describe "allocations" do
  # Objects allocated per run of the block, averaged over +times+ runs.
  def allocations(times = 100, &block)
    before = GC.stat(:total_allocated_objects)
    times.times(&block)
    (GC.stat(:total_allocated_objects) - before) / times.to_f
  end

  it "parses a bare item in two objects" do
    input = "42"
    Fast::SFV.parse_item(input)
    # The Parser instance and the Item.
    expect(allocations { Fast::SFV.parse_item(input) }).to be(:<, 3)
  end

  it "parses an item with parameters in seven objects" do
    input = "5; foo=bar; a=1; b=?0"
    Fast::SFV.parse_item(input)
    # The Parser, the Item, the parameter Hash, the three parameter key
    # Strings and the token value's String, which #to_sym then interns.
    expect(allocations { Fast::SFV.parse_item(input) }).to be(:<, 8)
  end

  it "parses a string item in three objects" do
    input = "\"foo bar\""
    Fast::SFV.parse_item(input)
    # The Parser, the Item and the one content slice.
    expect(allocations { Fast::SFV.parse_item(input) }).to be(:<, 4)
  end

  it "parses a byte sequence item in three objects" do
    input = ":aGVsbG8=:"
    Fast::SFV.parse_item(input)
    # The Parser, the Item and the decoded byte String; items with no
    # parameters share the one frozen empty Hash.
    expect(allocations { Fast::SFV.parse_item(input) }).to be(:<, 4)
  end

  it "parses a display string item in four objects" do
    input = "%\"f%c3%bc\""
    Fast::SFV.parse_item(input)
    # The Parser, the Item, the DisplayString and its decoded byte buffer.
    expect(allocations { Fast::SFV.parse_item(input) }).to be(:<, 5)
  end

  it "parses a three-token list in eight objects" do
    input = "sugar, tea, rum"
    Fast::SFV.parse_list(input)
    # The Parser, the members Array, the three Items and the three token
    # Strings the Symbols are interned from.
    expect(allocations { Fast::SFV.parse_list(input) }).to be(:<, 9)
  end

  it "parses a multi-line list in five objects" do
    input = ["\"foo", "bar\""]
    Fast::SFV.parse_list(input)
    # The Parser, the joined field value, the members Array, the Item and
    # the one content slice.
    expect(allocations { Fast::SFV.parse_list(input) }).to be(:<, 6)
  end

  it "parses a mixed dictionary in eleven objects" do
    input = "a=1;b=2, c=(1 2)"
    Fast::SFV.parse_dict(input)
    # The Parser, the dictionary Hash and its three key Strings, two plain
    # Items, the parameter Hash with its key, and the InnerList with its
    # items Array and two member Items.
    expect(allocations { Fast::SFV.parse_dict(input) }).to be(:<, 12)
  end

  # Serialize budgets, measured on Ruby 4.0.10, then frozen: a bare item
  # 1, an item with parameters 1, a decimal item 2 (the Float#to_s text
  # its digits are read from — the one unavoidable temporary), a list 1,
  # a dictionary 1. The output String only, whatever the member count:
  # the emission appends into the one buffer, spelling integers by
  # division and tokens, strings and keys whole, so a 100-member list
  # is still 1.
  it "serializes a bare item in one object" do
    item = Fast::SFV::Item.new(42, {})
    Fast::SFV.serialize_item(item)
    # The output String only — 1 object.
    expect(allocations { Fast::SFV.serialize_item(item) }).to be(:<, 2)
  end

  it "serializes an item with parameters in one object" do
    item = Fast::SFV::Item.new(5, { "foo" => :bar, "a" => 1, "b" => false, "c" => true })
    Fast::SFV.serialize_item(item)
    # The output String only — 1 object: the keys, the token and the
    # digits all append into the one buffer.
    expect(allocations { Fast::SFV.serialize_item(item) }).to be(:<, 2)
  end

  it "serializes a decimal item in two objects" do
    item = Fast::SFV::Item.new(1.23, {})
    Fast::SFV.serialize_item(item)
    # The output String and the decimal's shortest-form text — 2
    # objects, the unavoidable temporary the as-written digits are
    # read from; the mantissa itself accumulates in place.
    expect(allocations { Fast::SFV.serialize_item(item) }).to be(:<, 3)
  end

  it "serializes a list in one object" do
    list = [Fast::SFV::Item.new(1, {}), Fast::SFV::InnerList.new([Fast::SFV::Item.new(2, {})], { "a" => 1 })]
    Fast::SFV.serialize_list(list)
    # The output String only — 1 object: inner lists and parameters
    # included, no per-member temporaries.
    expect(allocations { Fast::SFV.serialize_list(list) }).to be(:<, 2)
  end

  it "serializes a dictionary in one object" do
    dictionary = {
      "a" => Fast::SFV::Item.new(false, {}),
      "b" => Fast::SFV::Item.new(true, {}),
      "c" => Fast::SFV::InnerList.new([Fast::SFV::Item.new(1, {}), Fast::SFV::Item.new(2, {})], {})
    }
    Fast::SFV.serialize_dict(dictionary)
    # The output String only — 1 object, short forms and "=" members
    # alike (a decimal member would add its 1 text object).
    expect(allocations { Fast::SFV.serialize_dict(dictionary) }).to be(:<, 2)
  end
end
