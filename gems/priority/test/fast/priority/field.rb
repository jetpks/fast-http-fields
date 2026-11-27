# frozen_string_literal: true

require "fast/priority"

describe Fast::Priority do
  # The ParseError a semantic violation raised, or nil — the frozen
  # offset pins are read off it.
  def semantic_error_of(input)
    Fast::Priority.parse!(input)
    nil
  rescue Fast::Priority::ParseError => e
    e
  end

  describe ".parse" do
    it "reads the RFC 9218 4.1 example: u=0" do
      priority = Fast::Priority.parse("u=0")
      expect(priority.urgency).to be(:==, 0)
      expect(priority.incremental).to be(:==, false)
    end

    it "reads the RFC 9218 4.2 example: u=5, i" do
      priority = Fast::Priority.parse("u=5, i")
      expect(priority.urgency).to be(:==, 5)
      expect(priority.incremental).to be(:==, true)
    end

    it "answers the defaults for an absent field" do
      priority = Fast::Priority.parse("")
      expect(priority.urgency).to be(:==, 3)
      expect(priority.incremental).to be(:==, false)
      expect(priority.to_s).to be(:==, "")
      expect(priority.members).to be(:empty?)
      expect(priority.unknown).to be(:empty?)
    end

    it "answers the defaults for a malformed field" do
      priority = Fast::Priority.parse("!!")
      expect(priority.urgency).to be(:==, 3)
      expect(priority.incremental).to be(:==, false)
      expect(priority.to_s).to be(:==, "")
      expect(priority.members).to be(:empty?)
    end

    it "ignores an out-of-range urgency, and only the effective member counts" do
      expect(Fast::Priority.parse("u=9").urgency).to be(:==, 3)
      expect(Fast::Priority.parse("u=-1").urgency).to be(:==, 3)
      # RFC 9651 4.2's last-wins applies before the 9218 4 filter.
      expect(Fast::Priority.parse("u=1, u=9").urgency).to be(:==, 3)
      expect(Fast::Priority.parse("u=9, u=1").urgency).to be(:==, 1)
    end

    it "ignores a wrong-typed urgency" do
      ["u=fast", "u=3.5", "u=?0", "u=(1 2)", "u"].each do |input|
        expect(Fast::Priority.parse(input).urgency).to be(:==, 3)
        expect(Fast::Priority.parse(input).members).to be(:empty?)
      end
    end

    it "ignores a wrong-typed incremental" do
      expect(Fast::Priority.parse("i=1").incremental).to be(:==, false)
      expect(Fast::Priority.parse("i=fast").incremental).to be(:==, false)
      expect(Fast::Priority.parse("i=1").members).to be(:empty?)
    end

    it "reads the Boolean incremental forms" do
      expect(Fast::Priority.parse("i").incremental).to be(:==, true)
      expect(Fast::Priority.parse("i=?1").incremental).to be(:==, true)
      expect(Fast::Priority.parse("i=?0").incremental).to be(:==, false)
      expect(Fast::Priority.parse("i=?0").to_s).to be(:==, "i=?0")
    end

    it "passes unknown members through as parsed" do
      priority = Fast::Priority.parse("u=1, i, foo=bar")
      expect(priority.urgency).to be(:==, 1)
      expect(priority.incremental).to be(:==, true)
      expect(priority.unknown.keys).to be(:==, ["foo"])
      expect(priority.unknown["foo"].value).to be(:==, "bar")
      expect(priority.members.keys).to be(:==, %w[u i foo])
    end

    it "preserves SFV parameters on a kept u member" do
      priority = Fast::Priority.parse("u=3;q=1")
      expect(priority.urgency).to be(:==, 3)
      expect(priority.to_s).to be(:==, "u=3;q=1")
    end

    it "combines an Array of field lines with \", \" and accepts a plain String" do
      priority = Fast::Priority.parse(["u=5", "i"])
      expect(priority.urgency).to be(:==, 5)
      expect(priority.incremental).to be(:==, true)
      expect(Fast::Priority.parse(["u=1", "u=9"]).urgency).to be(:==, 3)
    end

    it "round-trips a parsed value byte-exactly" do
      expect(Fast::Priority.parse("u=5, i, foo=bar").to_s).to be(:==, "u=5, i, foo=bar")
      expect(Fast::Priority.parse("foo=bar, u=5").to_s).to be(:==, "foo=bar, u=5")
    end

    it "answers frozen value objects" do
      priority = Fast::Priority.parse("u=1, i, foo=bar")
      expect(priority.frozen?).to be(:==, true)
      expect(priority.members.frozen?).to be(:==, true)
      expect(priority.unknown.frozen?).to be(:==, true)
    end

    it "raises TypeError for a non-String, non-Array input" do
      [42, nil, 3.14, :sym, {}].each do |wrong|
        expect { Fast::Priority.parse(wrong) }.to raise_exception(::TypeError)
      end
      expect { Fast::Priority.parse(["u=1", 42]) }.to raise_exception(::TypeError)
    end
  end

  describe ".parse!" do
    it "wraps the SFV Dictionary failure with its offset" do
      error = nil
      begin
        Fast::Priority.parse!("!!")
      rescue Fast::Priority::ParseError => e
        error = e
      end
      expect(error).to be(:kind_of?, Fast::Priority::ParseError)
      expect(error.offset).to be(:==, 0)
    end

    it "returns the strict view of a valid field" do
      priority = Fast::Priority.parse!("u=1, i, foo=bar;q=2")
      expect(priority.urgency).to be(:==, 1)
      expect(priority.incremental).to be(:==, true)
      expect(priority.to_s).to be(:==, "u=1, i, foo=bar;q=2")
    end

    it "positions a semantic error at the offending member's value" do
      ["u=9", "i=1", "u=(1 2)", %(u=("a,b" 2))].each do |input|
        error = semantic_error_of(input)
        expect(error).to be(:kind_of?, Fast::Priority::ParseError)
        expect(error.offset).to be(:==, 2)
      end
    end

    it "positions an implicit-true member at its key's end" do
      expect(semantic_error_of("u").offset).to be(:==, 1)
    end

    it "positions the error at the effective, last-wins member" do
      expect(semantic_error_of("u=1, u=9").offset).to be(:==, 7)
      expect(semantic_error_of(["u=1", "u=9"]).offset).to be(:==, 7)
    end

    it "positions after a display string whose content ends in a backslash" do
      # RFC 9651 §4.2.10: a display string's backslash is literal
      # content and only DQUOTE closes, so x=%"\" is a legal member
      # the error walk must cross intact.
      expect(semantic_error_of(%(x=%"\\", u=9)).offset).to be(:==, 10)
      expect(semantic_error_of(%(x=%"a", u=9)).offset).to be(:==, 10)
    end

    it "positions after a parameter on the valueless member" do
      # §4.2.2 step 3 parses parameters on the implicit Boolean true,
      # so a;b=1 is a legal member the error walk must cross intact.
      expect(semantic_error_of("a;b=1, u=9").offset).to be(:==, 9)
      expect(semantic_error_of("a, u=9").offset).to be(:==, 5)
    end

    it "raises TypeError for a wrong input type, as parse" do
      [42, nil, :sym].each do |wrong|
        expect { Fast::Priority.parse!(wrong) }.to raise_exception(::TypeError)
      end
    end
  end

  describe ".valid?" do
    it "mirrors the strict parse with a boolean" do
      expect(Fast::Priority.valid?("")).to be(:==, true)
      expect(Fast::Priority.valid?("u=0")).to be(:==, true)
      expect(Fast::Priority.valid?("u=5, i, foo=bar")).to be(:==, true)
      expect(Fast::Priority.valid?("!!")).to be(:==, false)
      expect(Fast::Priority.valid?("u=9")).to be(:==, false)
      expect(Fast::Priority.valid?("i=1")).to be(:==, false)
      expect(Fast::Priority.valid?(nil)).to be(:==, false)
      expect(Fast::Priority.valid?(42)).to be(:==, false)
    end
  end

  describe Fast::Priority::Parameters do
    it "builds the canonical forms from the keywords" do
      expect(Fast::Priority::Parameters.new(urgency: 1).to_s).to be(:==, "u=1")
      expect(Fast::Priority::Parameters.new(urgency: 1, incremental: true).to_s).to be(:==, "u=1, i")
      expect(Fast::Priority::Parameters.new(incremental: true).to_s).to be(:==, "i")
      expect(Fast::Priority::Parameters.new.to_s).to be(:==, "")
    end

    it "answers the defaults for an absent member at construction" do
      parameters = Fast::Priority::Parameters.new(urgency: 1)
      expect(parameters.incremental).to be(:==, false)
      expect(parameters.members.keys).to be(:==, ["u"])
      expect(Fast::Priority::Parameters.new.urgency).to be(:==, 3)
    end

    it "carries the unknown members after the known ones" do
      unknown = { "foo" => Fast::SFV::Item.new(Fast::SFV::Token.new("bar"), {}) }
      parameters = Fast::Priority::Parameters.new(urgency: 1, unknown: unknown)
      expect(parameters.to_s).to be(:==, "u=1, foo=bar")
      expect(parameters.unknown.keys).to be(:==, ["foo"])
    end

    it "raises SerializeError for an out-of-range or wrong-typed urgency" do
      [9, -1, "1", 3.0, true].each do |bad|
        expect { Fast::Priority::Parameters.new(urgency: bad) }.to raise_exception(Fast::Priority::SerializeError)
      end
    end

    it "raises SerializeError for a non-Boolean incremental" do
      [1, "true", 0].each do |bad|
        expect { Fast::Priority::Parameters.new(incremental: bad) }.to raise_exception(Fast::Priority::SerializeError)
      end
    end

    it "raises SerializeError for a bad unknown member" do
      expect { Fast::Priority::Parameters.new(unknown: { "u" => Fast::SFV::Item.new(1, {}) }) }
        .to raise_exception(Fast::Priority::SerializeError)
      expect { Fast::Priority::Parameters.new(unknown: { "foo" => 1 }) }
        .to raise_exception(Fast::Priority::SerializeError)
      expect { Fast::Priority::Parameters.new(unknown: "foo") }
        .to raise_exception(Fast::Priority::SerializeError)
      item = Fast::SFV::Item.new(1, {})
      inner = Fast::Priority::Parameters.new(unknown: { "foo" => Fast::SFV::InnerList.new([item], {}) })
      expect(inner.to_s).to be(:==, "foo=(1)")
      expect(inner.unknown.frozen?).to be(:==, true)
    end

    it "rewraps a substrate SerializeError into Fast::Priority's own" do
      # A hand-built unknown member that passes construction (the
      # check reads the class) but cannot serialize must still raise
      # a Fast::Priority failure — the one-rescue guarantee: every
      # failure this gem raises descends from Fast::Priority::Error.
      bad = Fast::Priority::Parameters.new(unknown: { "foo" => Fast::SFV::Item.new(:sym, {}) })
      expect { bad.to_s }.to raise_exception(Fast::Priority::SerializeError)
      error = nil
      begin
        bad.to_s
      rescue Fast::Priority::SerializeError => e
        error = e
      end
      expect(error).to be(:kind_of?, Fast::Priority::Error)
      expect(error.offset).to be(:==, 4)
      expect { Fast::Priority::H2.encode_payload(5, bad) }
        .to raise_exception(Fast::Priority::SerializeError)
      expect { Fast::Priority::H3.encode_payload(5, bad) }
        .to raise_exception(Fast::Priority::SerializeError)
    end

    it "merges by the RFC 9218 8 example" do
      merged = Fast::Priority.parse("u=5, i").merge(Fast::Priority.parse("u=1"))
      expect(merged.urgency).to be(:==, 1)
      expect(merged.incremental).to be(:==, true)
      expect(merged.to_s).to be(:==, "u=1, i")
      expect(merged.frozen?).to be(:==, true)
    end

    it "keeps a parameter the other omits, per 9218 8" do
      expect(Fast::Priority.parse("u=5").merge(Fast::Priority.parse("i")).urgency).to be(:==, 5)
      expect(Fast::Priority.parse("u=5").merge(Fast::Priority.parse("i")).incremental).to be(:==, true)
    end

    it "unions the unknown members with the other's winning collisions" do
      merged = Fast::Priority.parse("foo=1, u=3").merge(Fast::Priority.parse("foo=2, bar=3"))
      expect(merged.to_s).to be(:==, "foo=2, u=3, bar=3")
    end

    it "leaves both inputs untouched and answers a new object" do
      left = Fast::Priority.parse("u=5, i")
      right = Fast::Priority.parse("u=1")
      merged = left.merge(right)
      expect(left.to_s).to be(:==, "u=5, i")
      expect(right.to_s).to be(:==, "u=1")
      expect(merged.equal?(left)).to be(:==, false)
      expect(merged.equal?(right)).to be(:==, false)
    end

    it "raises TypeError for a non-Parameters other" do
      expect { Fast::Priority.parse("u=1").merge("u=2") }.to raise_exception(::TypeError)
    end

    it "compares by canonical wire form" do
      expect(Fast::Priority.parse("u=1")).to be(:==, Fast::Priority::Parameters.new(urgency: 1))
      expect(Fast::Priority.parse("u=3;q=1") == Fast::Priority::Parameters.new(urgency: 3)).to be(:==, false)
      expect(Fast::Priority.parse("u=1").hash).to be(:==, Fast::Priority::Parameters.new(urgency: 1).hash)
      expect(Fast::Priority.parse("u=1") == "u=1").to be(:==, false)
    end

    it "inspects as the wire form" do
      expect(Fast::Priority.parse("u=5, i").inspect).to be(:==, "#<Fast::Priority::Parameters u=5, i>")
      expect(Fast::Priority.parse("").inspect).to be(:==, "#<Fast::Priority::Parameters>")
    end
  end
end
