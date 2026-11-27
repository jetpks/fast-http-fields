# frozen_string_literal: true

require "fast/proxy_status"

describe Fast::TargetedCacheControl do
  # The ParseError a strict parse raised, or nil — the frozen offset
  # pins are read off it.
  def strict_error_of(input)
    Fast::TargetedCacheControl.parse!(input)
    nil
  rescue Fast::TargetedCacheControl::ParseError => e
    e
  end

  # The SerializeError a construction raised, or nil.
  def serialize_error_of
    yield
    nil
  rescue Fast::TargetedCacheControl::SerializeError => e
    e
  end

  # The section 2.1 inference set: one member of each inferred type —
  # valueless, quoted, token, decimal.
  def inference_input
    'no-store, private="Foo, Bar", x-thing=foo, y=1.5'
  end

  describe ".parse" do
    it "reads the section 3.1 example" do
      field = Fast::TargetedCacheControl.parse("max-age=600")
      expect(field["max-age"]).to be(:==, 600)
      expect(field["max-age"]).to be(:kind_of?, Integer)
      expect(field.to_s).to be(:==, "max-age=600")
    end

    it "reads the none example — valueless, unregistered, passing through" do
      field = Fast::TargetedCacheControl.parse("none")
      expect(field["none"]).to be(:==, true)
      expect(field.to_s).to be(:==, "none")
      expect(field.violating).to be(:==, [])
    end

    it "reads the section 2.1 inference mapping" do
      field = Fast::TargetedCacheControl.parse(inference_input)
      expect(field["no-store"]).to be(:==, true)
      expect(field["private"]).to be(:==, "Foo, Bar")
      expect(field["private"]).to be(:instance_of?, String)
      expect(field["x-thing"]).to be(:kind_of?, Fast::SFV::Token)
      expect(field["y"]).to be(:==, 1.5)
      expect(field.to_s).to be(:==, inference_input)
      expect(field.violating).to be(:==, [])
    end

    it "reads a quoted no-cache field-name list" do
      field = Fast::TargetedCacheControl.parse('no-cache="Set-Cookie, Foo"')
      expect(field["no-cache"]).to be(:==, "Set-Cookie, Foo")
      expect(field.violating).to be(:==, [])
    end

    it "preserves a violating known directive and flags it" do
      field = Fast::TargetedCacheControl.parse("max-age=60.5")
      expect(field["max-age"]).to be(:==, 60.5)
      expect(field.violating).to be(:==, ["max-age"])
      expect(field.to_s).to be(:==, "max-age=60.5")
    end

    it "flags per-directive and keeps the rest of the field readable" do
      field = Fast::TargetedCacheControl.parse("max-age=abc, no-store, x-custom=3")
      expect(field.violating).to be(:==, ["max-age"])
      expect(field["no-store"]).to be(:==, true)
      expect(field["x-custom"]).to be(:==, 3)
      expect(field.size).to be(:==, 3)
    end

    it "flags a value outside the inferred types, preserving it" do
      byte_sequence = Fast::TargetedCacheControl.parse("x=:AAAA:")
      expect(byte_sequence.violating).to be(:==, ["x"])
      expect(byte_sequence["x"].encoding).to be(:==, Encoding::ASCII_8BIT)
      inner_list = Fast::TargetedCacheControl.parse("a=(1 2)")
      expect(inner_list.violating).to be(:==, ["a"])
      expect(inner_list["a"]).to be(:kind_of?, Array)
      expect(inner_list["a"].map(&:value)).to be(:==, [1, 2])
      expect(inner_list.to_s).to be(:==, "a=(1 2)")
    end

    it "answers the raw member view with parameters preserved" do
      field = Fast::TargetedCacheControl.parse("max-age=600;foo=1")
      expect(field.violating).to be(:==, [])
      expect(field.members["max-age"].params).to be(:==, { "foo" => 1 })
      expect(field.to_s).to be(:==, "max-age=600;foo=1")
    end

    it "ignores an empty or malformed field entirely" do
      ["", "!!", "9foo", "a=1,"].each do |bad|
        expect(Fast::TargetedCacheControl.parse(bad).empty?).to be(:==, true)
        expect(Fast::TargetedCacheControl.parse(bad).to_s).to be(:==, "")
        expect(Fast::TargetedCacheControl.parse(bad).violating).to be(:==, [])
      end
      expect(Fast::TargetedCacheControl.parse("!!").equal?(Fast::TargetedCacheControl.parse("")))
        .to be(:==, true)
    end

    it "combines field lines with last-wins, first position kept" do
      combined = Fast::TargetedCacheControl.parse(["a=1", "a=2"])
      expect(combined["a"]).to be(:==, 2)
      expect(combined.to_s).to be(:==, "a=2")
      expect(combined.size).to be(:==, 1)
      lines = Fast::TargetedCacheControl.parse(["a=1", "b=2"])
      expect(lines.size).to be(:==, 2)
      expect(lines.keys).to be(:==, %w[a b])
    end

    it "raises TypeError for a non-String, non-Array input" do
      [42, nil, 3.14, :sym, {}].each do |wrong|
        expect { Fast::TargetedCacheControl.parse(wrong) }.to raise_exception(::TypeError)
      end
      expect { Fast::TargetedCacheControl.parse(["a=1", 42]) }.to raise_exception(::TypeError)
    end

    it "answers frozen value objects" do
      field = Fast::TargetedCacheControl.parse("max-age=600")
      expect(field.frozen?).to be(:==, true)
      expect(field.members.frozen?).to be(:==, true)
      expect(field.keys.frozen?).to be(:==, true)
      expect(field.violating.frozen?).to be(:==, true)
      expect(field.members["max-age"].frozen?).to be(:==, true)
    end

    it "answers the reader set over the members" do
      field = Fast::TargetedCacheControl.parse("max-age=600, no-store")
      expect(field.key?("max-age")).to be(:==, true)
      expect(field.key?("no-cache")).to be(:==, false)
      expect(field["no-cache"]).to be(:==, nil)
      expect(field.size).to be(:==, 2)
      expect(field.empty?).to be(:==, false)
      directives = []
      field.each { |key, value| directives << [key, value] }
      expect(directives).to be(:==, [["max-age", 600], ["no-store", true]])
    end

    it "answers an Enumerator from #each without a block" do
      field = Fast::TargetedCacheControl.parse("max-age=600, no-store")
      enumerator = field.each
      expect(enumerator).to be(:kind_of?, ::Enumerator)
      expect(enumerator.to_a).to be(:==, [["max-age", 600], ["no-store", true]])
      expect(enumerator.each.next).to be(:==, ["max-age", 600])
    end
  end

  describe ".parse!" do
    it "wraps the SFV Dictionary failure with its offset" do
      error = strict_error_of("!!")
      expect(error).to be(:kind_of?, Fast::TargetedCacheControl::ParseError)
      expect(error.offset).to be(:==, 0)
    end

    it "positions violations at the value, frozen pins" do
      pins = {
        "max-age=abc" => 8, "max-age=60.5" => 8, "max-age=\"60\"" => 8, "no-store=?0" => 9, "no-store=1" => 9,
        "no-cache=foo" => 9, "private=x" => 8, "must-revalidate=1" => 16, "max-age" => 7, "x=:AAAA:" => 2,
        "a=(1 2)" => 2
      }
      pins.each do |input, offset|
        error = strict_error_of(input)
        expect(error).to be(:kind_of?, Fast::TargetedCacheControl::ParseError)
        expect(error.offset).to be(:==, offset)
      end
    end

    it "raises the first offender in dictionary order, the later member at its own value" do
      expect(strict_error_of("max-age=600, no-store=1").offset).to be(:==, 22)
      expect(strict_error_of("a=1, max-age=abc").offset).to be(:==, 13)
    end

    it "positions a duplicated key at its last occurrence" do
      error = strict_error_of(["max-age=1", "max-age=abc"])
      expect(error).to be(:kind_of?, Fast::TargetedCacheControl::ParseError)
      expect(error.offset).to be(:==, 19)
    end

    it "positions after a parameter on the valueless member" do
      # RFC 9651 §4.2.2 step 3 parses parameters on the implicit
      # Boolean true, so foo; a=1 is a legal member the positioning
      # must cross intact — the later bar is raised at its own value.
      expect(strict_error_of("foo; a=1, bar=:AQID:").offset).to be(:==, 14)
      expect(strict_error_of("foo, bar=:AQID:").offset).to be(:==, 9)
    end

    it "positions after a display-string parameter ending in a backslash" do
      # §4.2.10 again, as a parameter value: the later bar is raised at
      # its own value, never lost to the walk.
      expect(strict_error_of(%(foo; a=%"\\", bar=:AQID:)).offset).to be(:==, 17)
    end

    it "returns the strict view of a valid field, parameters preserved" do
      field = Fast::TargetedCacheControl.parse!("max-age=600;foo=1, none")
      expect(field["max-age"]).to be(:==, 600)
      expect(field["none"]).to be(:==, true)
      expect(Fast::TargetedCacheControl.parse!("").empty?).to be(:==, true)
    end

    it "raises TypeError for a wrong input type, as parse" do
      [42, nil, :sym].each do |wrong|
        expect { Fast::TargetedCacheControl.parse!(wrong) }.to raise_exception(::TypeError)
      end
    end
  end

  describe ".valid?" do
    it "mirrors the strict parse with a boolean" do
      expect(Fast::TargetedCacheControl.valid?("max-age=600")).to be(:==, true)
      expect(Fast::TargetedCacheControl.valid?("no-store")).to be(:==, true)
      expect(Fast::TargetedCacheControl.valid?("none")).to be(:==, true)
      expect(Fast::TargetedCacheControl.valid?('no-cache="Set-Cookie, Foo"')).to be(:==, true)
      expect(Fast::TargetedCacheControl.valid?("")).to be(:==, true)
      expect(Fast::TargetedCacheControl.valid?("max-age=600;foo=1")).to be(:==, true)
      expect(Fast::TargetedCacheControl.valid?(inference_input)).to be(:==, true)
      expect(Fast::TargetedCacheControl.valid?("max-age=abc")).to be(:==, false)
      expect(Fast::TargetedCacheControl.valid?("max-age")).to be(:==, false)
      expect(Fast::TargetedCacheControl.valid?("max-age=60.5")).to be(:==, false)
      expect(Fast::TargetedCacheControl.valid?("x=:AAAA:")).to be(:==, false)
      expect(Fast::TargetedCacheControl.valid?("a=(1 2)")).to be(:==, false)
      expect(Fast::TargetedCacheControl.valid?("!!")).to be(:==, false)
      expect(Fast::TargetedCacheControl.valid?(5)).to be(:==, false)
      expect(Fast::TargetedCacheControl.valid?(nil)).to be(:==, false)
    end
  end

  describe "construction" do
    it "answers the canonical form from a Hash" do
      field = Fast::TargetedCacheControl.new({ "max-age" => 600, "no-store" => true })
      expect(field.to_s).to be(:==, "max-age=600, no-store")
      expect(field.size).to be(:==, 2)
      expect(Fast::TargetedCacheControl.new({}).to_s).to be(:==, "")
      expect(Fast::TargetedCacheControl.new({}).empty?).to be(:==, true)
    end

    it "emits a digit-initial and star-initial String quoted, a Token bare" do
      expect(Fast::TargetedCacheControl.new({ "x-custom" => "9abc" }).to_s).to be(:==, 'x-custom="9abc"')
      expect(Fast::TargetedCacheControl.new({ "x-custom" => "*foo" }).to_s).to be(:==, 'x-custom="*foo"')
      expect(Fast::TargetedCacheControl.new({ "x-custom" => Fast::SFV::Token.new("foo") }).to_s)
        .to be(:==, "x-custom=foo")
    end

    it "refuses a known directive of the wrong type" do
      # An Array of pairs, not a Hash literal: a literal with repeated
      # keys collapses to the last pair silently.
      wrong = [
        %w[max-age 600], ["max-age", 1.5], ["max-age", true], ["no-store", false], ["no-store", 1],
        ["no-cache", Fast::SFV::Token.new("foo")], ["private", 5], ["must-revalidate", 0]
      ]
      wrong.each do |key, value|
        error = serialize_error_of { Fast::TargetedCacheControl.new({ key => value }) }
        expect(error).to be(:kind_of?, Fast::TargetedCacheControl::SerializeError)
      end
    end

    it "refuses a value outside the inferred types" do
      ["raw".b, nil, :sym, [1, 2]].each do |bad|
        error = serialize_error_of { Fast::TargetedCacheControl.new({ "x" => bad }) }
        expect(error).to be(:kind_of?, Fast::TargetedCacheControl::SerializeError)
      end
    end

    it "refuses keys outside the key grammar and non-Hash members" do
      ["Max-Age", 5, nil, "with space"].each do |bad|
        error = serialize_error_of { Fast::TargetedCacheControl.new({ bad => 600 }) }
        expect(error).to be(:kind_of?, Fast::TargetedCacheControl::SerializeError)
      end
      expect(serialize_error_of { Fast::TargetedCacheControl.new("not a hash") })
        .to be(:kind_of?, Fast::TargetedCacheControl::SerializeError)
    end

    it "accepts the known types and unknown directives, emitting canonically" do
      field = Fast::TargetedCacheControl.new(
        {
          "max-age" => 600, "must-revalidate" => true, "no-store" => true, "no-cache" => "Set-Cookie, Foo",
          "private" => true, "s-maxage" => 120, "none" => Fast::SFV::Token.new("none"),
          "stale-while-revalidate" => 10, "y-decimal" => 1.5
        }
      )
      expect(field.violating).to be(:==, [])
      expect(field.to_s).to be(:==,
                               "max-age=600, must-revalidate, no-store, no-cache=\"Set-Cookie, Foo\", private, " \
                               "s-maxage=120, none=none, stale-while-revalidate=10, y-decimal=1.5")
    end

    it "freezes the values in place and answers a frozen value object" do
      members = { "x-custom" => "v".dup }
      field = Fast::TargetedCacheControl.new(members)
      expect(field.frozen?).to be(:==, true)
      expect(field.members.frozen?).to be(:==, true)
      expect(field.keys.frozen?).to be(:==, true)
      expect(field.violating).to be(:==, [])
      expect(members["x-custom"].frozen?).to be(:==, true)
    end
  end

  describe "to_s" do
    it "round-trips what parsed, violating values included" do
      inputs = [
        "max-age=600", "no-store", "none", 'no-cache="Set-Cookie, Foo"', "max-age=60.5",
        "max-age=600;foo=1", "a=(1 2)", inference_input
      ]
      inputs.each do |input|
        expect(Fast::TargetedCacheControl.parse(input).to_s).to be(:==, input)
      end
    end

    it "canonicalizes the explicit Boolean true valueless" do
      expect(Fast::TargetedCacheControl.parse("no-store=?1").to_s).to be(:==, "no-store")
      expect(Fast::TargetedCacheControl.parse("no-store=?0").to_s).to be(:==, "no-store=?0")
    end
  end

  describe "the data tables" do
    it "carries the five MUST-implement directives as frozen data" do
      expected = {
        "max-age" => "an Integer", "must-revalidate" => "Boolean true", "no-store" => "Boolean true",
        "no-cache" => "Boolean true or a String", "private" => "Boolean true or a String"
      }
      expect(Fast::TargetedCacheControl::DIRECTIVES).to be(:==, expected)
      expect(Fast::TargetedCacheControl::DIRECTIVES.frozen?).to be(:==, true)
    end

    it "carries the registered field name and no suffix matcher" do
      expect(Fast::TargetedCacheControl::FIELD_NAME).to be(:==, "CDN-Cache-Control")
      expect(Fast::TargetedCacheControl.respond_to?(:targeted_name?)).to be(:==, false)
      expect(Fast::TargetedCacheControl::INFERRED).to be(:kind_of?, String)
    end

    it "never gates a parse on the table: unknown directives pass through" do
      field = Fast::TargetedCacheControl.parse("x-extension=foo, max-age=600")
      expect(field.violating).to be(:==, [])
      expect(field["x-extension"]).to be(:==, "foo")
    end
  end

  describe "the error hierarchy" do
    it "descends from the gem root with both error shapes carrying offset" do
      expect(Fast::TargetedCacheControl::Error < Fast::ProxyStatus::Error).to be(:==, true)
      expect(Fast::TargetedCacheControl::ParseError < Fast::TargetedCacheControl::Error).to be(:==, true)
      expect(Fast::TargetedCacheControl::SerializeError < Fast::TargetedCacheControl::Error).to be(:==, true)
      expect(Fast::TargetedCacheControl::ParseError.new("message", 7).offset).to be(:==, 7)
      expect(Fast::TargetedCacheControl::SerializeError.new("message", 0).offset).to be(:==, 0)
    end
  end

  describe "equality" do
    it "compares by canonical wire form within the class" do
      one = Fast::TargetedCacheControl.parse("max-age=600, no-store")
      other = Fast::TargetedCacheControl.parse("max-age=600 , no-store")
      expect(one == other).to be(:==, true)
      expect(one.eql?(other)).to be(:==, true)
      expect(one.hash).to be(:==, other.hash)
      expect(one == Fast::TargetedCacheControl.parse("max-age=600")).to be(:==, false)
      expect(one == "max-age=600, no-store").to be(:==, false)
      expect(one == Fast::CacheStatus.parse("a, b")).to be(:==, false)
    end

    it "inspects with the class name and the wire form" do
      expect(Fast::TargetedCacheControl.parse("max-age=600").inspect)
        .to be(:==, "#<Fast::TargetedCacheControl max-age=600>")
      expect(Fast::TargetedCacheControl.new({}).inspect).to be(:==, "#<Fast::TargetedCacheControl>")
    end
  end
end
