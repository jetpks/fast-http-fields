# frozen_string_literal: true

require "fast/sfv"

# The two §4.2 corners a hand-rolled region walk gets wrong, as the
# substrate's own exact span pins: a display string whose content
# ends in a backslash (RFC 9651 §4.2.10 has no backslash escaping —
# only DQUOTE closes, backslash is literal content) and a valueless
# dictionary member carrying parameters (§4.2.2 step 3 parses them:
# `a;q=1` is legal). Both parse; the scan must position both.
BACKSLASH_DISPLAY = "foo=%\"\\\""
PARAMS_ON_VALUELESS = "a;q=1, b=11, a=3"

# The member shapes that follow each corner, with and without the
# trigger: a value after the display string, a duplicate dictionary
# key after it, list members after it, parameters after it — and the
# same fields with the corner removed, the control every pin
# positions against.
URGENCY_AFTER_DISPLAY = "x=%\"\\\", u=9"
URGENCY_AFTER_DISPLAY_CONTROL = "x=%\"a\", u=9"
DUPLICATE_AFTER_DISPLAY = "sha-256=3, foo=%\"\\\", sha-256=11"
DUPLICATE_CONTROL = "a, md5=11, a=3"
MEMBER_AFTER_DISPLAY_PARAMS = "a; x=%\"\\\"; error=3"
LIST_AFTER_DISPLAY = "a; x=%\"\\\", 5"
LIST_AFTER_DISPLAY_CONTROL = "a; x=%\"a\", 5"
BYTES_AFTER_DISPLAY = ":AAAA:, %\"\\\", 5"
URGENCY_AFTER_PARAMS = "a;b=1, u=9"
VALUE_AFTER_PARAMS = "foo; a=1, bar=:AQID:"
VALUE_AFTER_PARAMS_CONTROL = "foo, bar=:AQID:"

# The field line that cannot combine — the reject policy the scan
# shares with the parse entry points (the one FieldValue
# implementation).
UNJOINABLE_LINES = ["a".b, "b".dup.force_encoding("UTF-16LE")].freeze

# Malformed content, each with the §4.2 shape the scan walks: the
# scan must raise the parse's own message at the parse's own offset.
MALFORMED = [
  ["foo bar", :item],
  ["a=1 b=2", :dictionary],
  ["a=1,", :dictionary],
  ["\"unclosed", :item],
  [":aGVsbG8=", :item],
  ["?2", :item],
  ["a=%\"x", :dictionary],
  ["a=%\"%e9a\"", :dictionary]
].freeze

# The scan and parse entry points each §4.2 shape walks — the
# strictness comparison's pair.
ENTRY_POINTS = {
  item: %i[regions_item parse_item],
  list: %i[regions_list parse_list],
  dictionary: %i[regions_dict parse_dict]
}.freeze

describe Fast::SFV do
  def error_of
    yield
    nil
  rescue Fast::SFV::ParseError => e
    e
  end

  describe ".regions_dict" do
    it "positions the display string ending in a backslash (the §4.2.10 corner)" do
      member = Fast::SFV.regions_dict(BACKSLASH_DISPLAY).members[0]
      expect(member.key_start).to be(:==, 0)
      expect(member.key_end).to be(:==, 3)
      expect(member.value_start).to be(:==, 4)
      expect(member.value_end).to be(:==, 8)
      expect(member.start).to be(:==, 0)
      expect(member.end).to be(:==, 8)
      expect(member.params).to be(:==, [])
      # The display string's content is one backslash: the parse
      # succeeds, backslash being literal content (§4.2.10 step 4.5).
      expect(Fast::SFV.parse_dict(BACKSLASH_DISPLAY)["foo"].value.value).to be(:==, "\\")
    end

    it "positions the valueless member with parameters and the last-wins rebound (the §4.2.2 step 3 corner)" do
      regions = Fast::SFV.regions_dict(PARAMS_ON_VALUELESS)
      members = regions.members
      expect(members.size).to be(:==, 3)
      first, second, third = members
      # The valueless member: its value span is empty, at the key's
      # end — the position a value would be written at (§4.2.2
      # step 3's Boolean true).
      expect([first.key_start, first.key_end]).to be(:==, [0, 1])
      expect([first.value_start, first.value_end]).to be(:==, [1, 1])
      expect([first.params[0].key_start, first.params[0].key_end]).to be(:==, [2, 3])
      expect([first.params[0].value_start, first.params[0].value_end]).to be(:==, [4, 5])
      expect([second.key_start, second.key_end]).to be(:==, [7, 8])
      expect([second.value_start, second.value_end]).to be(:==, [9, 11])
      expect([third.key_start, third.key_end]).to be(:==, [13, 14])
      expect([third.value_start, third.value_end]).to be(:==, [15, 16])
      # The caller's reduction over #members lands on the effective
      # member: b's value at 9, the rebound a's value at 15.
      offsets = {}
      members.each { |m| offsets[regions.combined.byteslice(m.key_start, m.key_end - m.key_start)] = m.value_start }
      expect(offsets).to be(:==, { "a" => 15, "b" => 9 })
    end

    it "positions every member of the dictionary repro set exactly, with its controls" do
      members = Fast::SFV.regions_dict(URGENCY_AFTER_DISPLAY).members
      expect(members[1].value_start).to be(:==, 10)
      members = Fast::SFV.regions_dict(URGENCY_AFTER_DISPLAY_CONTROL).members
      expect(members[1].value_start).to be(:==, 10)
      members = Fast::SFV.regions_dict(DUPLICATE_AFTER_DISPLAY).members
      expect(members[1].value_start).to be(:==, 15)
      expect(members[1].value_end).to be(:==, 19)
      expect(members[2].value_start).to be(:==, 29)
      members = Fast::SFV.regions_dict(DUPLICATE_CONTROL).members
      expect(members[1].value_start).to be(:==, 7)
      members = Fast::SFV.regions_dict(URGENCY_AFTER_PARAMS).members
      expect(members[1].value_start).to be(:==, 9)
      members = Fast::SFV.regions_dict(VALUE_AFTER_PARAMS).members
      expect(members[1].value_start).to be(:==, 14)
      # The control: the same field without the desync trigger.
      members = Fast::SFV.regions_dict(VALUE_AFTER_PARAMS_CONTROL).members
      expect(members[1].value_start).to be(:==, 9)
    end

    it "combines an Array of field lines and provides the combined string itself" do
      regions = Fast::SFV.regions_dict(["a=1", "b=2"])
      expect(regions.combined).to be(:==, "a=1, b=2")
      expect(regions.members.size).to be(:==, 2)
      expect(regions.members[1].value_start).to be(:==, 7)
    end

    it "rejects a line that cannot combine with the parse's own reject policy" do
      scan = error_of { Fast::SFV.regions_list(UNJOINABLE_LINES) }
      parse = error_of { Fast::SFV.parse_list(UNJOINABLE_LINES) }
      expect([scan.message, scan.offset]).to be(:==, [parse.message, parse.offset])
      expect(scan.message).to be(:==, "a field line must be an ASCII-compatible encoding (got UTF-16LE) at offset 3")
      expect(scan.offset).to be(:==, 3)
    end

    it "answers an empty members Array for the empty dictionary" do
      expect(Fast::SFV.regions_dict("").members).to be(:==, [])
      expect(Fast::SFV.regions_dict([]).members).to be(:==, [])
    end
  end

  describe ".regions_list" do
    it "positions the members of the list repro set exactly, with its control" do
      members = Fast::SFV.regions_list(LIST_AFTER_DISPLAY).members
      expect(members.size).to be(:==, 2)
      expect(members[0].value_start).to be(:==, 0)
      expect(members[0].value_end).to be(:==, 1)
      expect(members[0].params[0].value_start).to be(:==, 5)
      expect(members[0].params[0].value_end).to be(:==, 9)
      expect(members[1].value_start).to be(:==, 11)
      members = Fast::SFV.regions_list(LIST_AFTER_DISPLAY_CONTROL).members
      expect(members[1].value_start).to be(:==, 11)

      members = Fast::SFV.regions_list(MEMBER_AFTER_DISPLAY_PARAMS).members
      expect(members.size).to be(:==, 1)
      expect(members[0].params.map { |p| [p.key_start, p.key_end] }).to be(:==, [[3, 4], [11, 16]])
      expect(members[0].params[1].value_start).to be(:==, 17)

      members = Fast::SFV.regions_list(BYTES_AFTER_DISPLAY).members
      expect(members.size).to be(:==, 3)
      expect(members[1].value_start).to be(:==, 8)
      expect(members[1].value_end).to be(:==, 12)
      expect(members[2].value_start).to be(:==, 14)
    end

    it "spans the whole member, parameters included — the slice a caller takes" do
      regions = Fast::SFV.regions_list(LIST_AFTER_DISPLAY)
      member = regions.members[0]
      text = regions.combined.byteslice(member.start, member.end - member.start)
      expect(text).to be(:==, "a; x=%\"\\\"")
      # The slice re-parses as one member: exactly what the parse kept.
      expect(Fast::SFV.parse_list(text).size).to be(:==, 1)
    end

    it "positions the inner list's own parameters, and walks its items' parameters" do
      regions = Fast::SFV.regions_list("(1 2);lvl=5")
      member = regions.members[0]
      expect(member.value_start).to be(:==, 0)
      expect(member.value_end).to be(:==, 5)
      expect(member.params[0].key_start).to be(:==, 6)
      expect(member.params[0].value_start).to be(:==, 10)

      # A display string ending in a backslash inside an inner list,
      # that item's parameters after it: the walk tracks both.
      member = Fast::SFV.regions_list("(%\"\\\"; a=1)").members[0]
      expect(member.value_start).to be(:==, 0)
      expect(member.value_end).to be(:==, 11)
    end

    it "answers an empty members Array for the empty list" do
      expect(Fast::SFV.regions_list("").members).to be(:==, [])
    end
  end

  describe ".regions_item" do
    it "positions the one member, after the leading SP and before the trailing" do
      member = Fast::SFV.regions_item("  42  ").members[0]
      expect(member.key_start).to be(:==, nil)
      expect(member.key_end).to be(:==, nil)
      expect(member.value_start).to be(:==, 2)
      expect(member.value_end).to be(:==, 4)
    end

    it "positions the item's parameters, on both value forms" do
      member = Fast::SFV.regions_item("5; foo=bar").members[0]
      expect(member.value_start).to be(:==, 0)
      expect(member.value_end).to be(:==, 1)
      param = member.params[0]
      expect([param.key_start, param.key_end]).to be(:==, [3, 6])
      expect([param.value_start, param.value_end]).to be(:==, [7, 10])
      # The valueless parameter: its value span is empty, at the key's
      # end (§4.2.3.2 step 2.5's Boolean true).
      member = Fast::SFV.regions_item("5; foo").members[0]
      expect([member.params[0].key_start, member.params[0].key_end]).to be(:==, [3, 6])
      expect([member.params[0].value_start, member.params[0].value_end]).to be(:==, [6, 6])
    end

    it "positions every bare item type" do
      ["42", "-1.23", "\"a\\\"b\"", "sugar", "?1", ":aGVsbG8=:", "@1659578233", "%\"a%25b\""].each do |input|
        regions = Fast::SFV.regions_item(input)
        member = regions.members[0]
        expect(member.value_start).to be(:==, 0)
        expect(member.value_end).to be(:==, input.bytesize)
        expect(regions.combined.byteslice(member.value_start, member.value_end - member.value_start)).to be(:==, input)
      end
    end
  end

  describe "the region scan's strictness" do
    it "raises the parse's own ParseError, message and offset, on malformed content" do
      MALFORMED.each do |input, shape|
        scan_entry, parse_entry = ENTRY_POINTS[shape]
        scan = error_of { Fast::SFV.public_send(scan_entry, input) }
        parse = error_of { Fast::SFV.public_send(parse_entry, input) }
        expect([scan.message, scan.offset]).to be(:==, [parse.message, parse.offset])
      end
    end

    it "raises TypeError for a wrong input type, as the parse entry points" do
      [42, nil, :sym].each do |wrong|
        expect { Fast::SFV.regions_item(wrong) }.to raise_exception(::TypeError)
        expect { Fast::SFV.regions_list(wrong) }.to raise_exception(::TypeError)
        expect { Fast::SFV.regions_dict(wrong) }.to raise_exception(::TypeError)
      end
      expect { Fast::SFV.regions_dict(["a=1", 42]) }.to raise_exception(::TypeError)
    end

    it "answers frozen regions and members" do
      regions = Fast::SFV.regions_dict(PARAMS_ON_VALUELESS)
      expect(regions).to be(:frozen?)
      expect(regions.members).to be(:frozen?)
      expect(regions.members[0]).to be(:frozen?)
      expect(regions.members[0].params).to be(:frozen?)
      expect(regions.members[0].params[0]).to be(:frozen?)
    end

    it "constructs directly from a shape, and rejects an unknown shape" do
      regions = Fast::SFV::Regions.new(PARAMS_ON_VALUELESS, :dictionary)
      expect(regions.members.size).to be(:==, 3)
      expect { Fast::SFV::Regions.new("a=1", :set) }.to raise_exception(ArgumentError)
    end
  end

  describe "the region scan's allocation budget" do
    # The scan serves the strict and diagnostic paths — cold — so its
    # budget is a measured ceiling, not a hot-path pin: the Regions
    # object, the members Array, one Region per member and one per
    # parameter, and the decoded byte buffer of a display string that
    # carries a percent escape. Measured on Ruby 4.0.10, then frozen:
    # the mixed dictionary 7, the three-token list 5, the bare item
    # 3, the display-string member 3 — 4 when it carries an escape
    # (the buffer). Every parse and serialize budget is unchanged by
    # the scan — the one FieldValue call the Parser now makes
    # allocates nothing, re-measured identical at base.
    def allocations(times = 100, &block)
      before = GC.stat(:total_allocated_objects)
      times.times(&block)
      (GC.stat(:total_allocated_objects) - before) / times.to_f
    end

    it "scans a mixed dictionary within its ceiling" do
      input = "a=1, b;foo=bar, c=(1 2)"
      Fast::SFV.regions_dict(input)
      expect(allocations { Fast::SFV.regions_dict(input) }).to be(:<, 9)
    end

    it "scans a three-token list, a bare item and display strings within their ceilings" do
      list = "sugar, tea, rum"
      item = "42"
      display = BACKSLASH_DISPLAY
      escaped = "foo=%\"a%25b\""
      Fast::SFV.regions_list(list)
      expect(allocations { Fast::SFV.regions_list(list) }).to be(:<, 7)
      Fast::SFV.regions_item(item)
      expect(allocations { Fast::SFV.regions_item(item) }).to be(:<, 5)
      Fast::SFV.regions_dict(display)
      expect(allocations { Fast::SFV.regions_dict(display) }).to be(:<, 6)
      Fast::SFV.regions_dict(escaped)
      expect(allocations { Fast::SFV.regions_dict(escaped) }).to be(:<, 6)
    end
  end
end
