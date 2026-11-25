# frozen_string_literal: true

require "json"
require "fast/sfv"

describe Fast::SFV do
  describe ".parse_item" do
    it "parses each of the eight bare item types" do
      expect(Fast::SFV.parse_item("42").value).to be(:==, 42)
      expect(Fast::SFV.parse_item("-1.23").value).to be(:==, -1.23)
      string = Fast::SFV.parse_item("\"foo\"").value
      expect(string).to be(:==, "foo")
      expect(string.is_a?(Fast::SFV::Token)).to be(:==, false)
      token = Fast::SFV.parse_item("sugar").value
      expect(token).to be(:kind_of?, Fast::SFV::Token)
      expect(token).to be(:==, "sugar")
      expect(Fast::SFV.parse_item("?1").value).to be(:==, true)
      expect(Fast::SFV.parse_item("?0").value).to be(:==, false)
      expect(Fast::SFV.parse_item(":aGVsbG8=:").value).to be(:==, "hello")
      expect(Fast::SFV.parse_item("@1659578233").value.value).to be(:==, 1_659_578_233)
      expect(Fast::SFV.parse_item("%\"f%c3%bc\"").value.value).to be(:==, "fü")
    end

    it "raises TypeError for every non-String, non-Array input" do
      [42, nil, 3.14, :sym, {}].each do |wrong|
        expect { Fast::SFV.parse_item(wrong) }.to raise_exception(::TypeError)
      end
    end

    it "raises a positioned ParseError for malformed content" do
      input = "foo bar"
      error = nil
      begin
        Fast::SFV.parse_item(input)
      rescue Fast::SFV::ParseError => e
        error = e
      end
      expect(error).to be(:kind_of?, Fast::SFV::ParseError)
      expect(error.offset).to be(:kind_of?, Integer)
      expect(error.offset).to be(:>=, 0)
      expect(error.offset).to be(:<=, input.bytesize)
      expect(error.message.length).to be(:>, 0)
    end
  end

  describe ".parse_list" do
    it "raises TypeError for a non-String input and a non-String line" do
      [42, nil, :sym].each do |wrong|
        expect { Fast::SFV.parse_list(wrong) }.to raise_exception(::TypeError)
      end
      expect { Fast::SFV.parse_list(["1", 42]) }.to raise_exception(::TypeError)
    end

    it "combines an Array of field lines with \", \" and accepts a plain String" do
      expect(Fast::SFV.parse_list(["\"foo", "bar\""]).map(&:value)).to be(:==, ["foo, bar"])
      expect(Fast::SFV.parse_list(%w[1 42]).map(&:value)).to be(:==, [1, 42])
      expect(Fast::SFV.parse_list("1, 42").map(&:value)).to be(:==, [1, 42])
    end

    it "parses empty input as the empty list, and an empty item fails" do
      expect(Fast::SFV.parse_list("")).to be(:==, [])
      expect(Fast::SFV.parse_list([])).to be(:==, [])
      expect { Fast::SFV.parse_item("") }.to raise_exception(Fast::SFV::ParseError)
    end
  end

  describe ".parse_dict" do
    it "raises TypeError for a non-String input and a non-String line" do
      [42, nil, :sym].each do |wrong|
        expect { Fast::SFV.parse_dict(wrong) }.to raise_exception(::TypeError)
      end
      expect { Fast::SFV.parse_dict(["a=1", 42]) }.to raise_exception(::TypeError)
    end

    it "combines an Array of field lines and answers an ordered Hash" do
      dictionary = Fast::SFV.parse_dict(["a=1", "b=2"])
      expect(dictionary.keys).to be(:==, %w[a b])
      expect(dictionary["a"].value).to be(:==, 1)
      expect(dictionary["b"].value).to be(:==, 2)
    end

    it "parses empty input as the empty dictionary" do
      expect(Fast::SFV.parse_dict("")).to be(:==, {})
      expect(Fast::SFV.parse_dict([])).to be(:==, {})
    end
  end

  describe "the error hierarchy" do
    it "roots ParseError at Fast::SFV::Error under StandardError" do
      expect(Fast::SFV::Error.ancestors).to be(:include?, StandardError)
      expect(Fast::SFV::ParseError.ancestors).to be(:include?, Fast::SFV::Error)
    end
  end

  describe ".valid_item?, .valid_list?, .valid_dict?" do
    it "answers false for a wrong input type instead of raising" do
      [42, nil, 3.14, :sym, {}].each do |wrong|
        expect(Fast::SFV.valid_item?(wrong)).to be(:==, false)
        expect(Fast::SFV.valid_list?(wrong)).to be(:==, false)
        expect(Fast::SFV.valid_dict?(wrong)).to be(:==, false)
      end
      expect(Fast::SFV.valid_list?(["1", 42])).to be(:==, false)
    end

    it "mirrors the parse entry points on content" do
      expect(Fast::SFV.valid_item?("@42")).to be(:==, true)
      expect(Fast::SFV.valid_item?("@ 42")).to be(:==, false)
      expect(Fast::SFV.valid_list?("1, 42")).to be(:==, true)
      expect(Fast::SFV.valid_list?("1,")).to be(:==, false)
      expect(Fast::SFV.valid_dict?("a=1")).to be(:==, true)
      expect(Fast::SFV.valid_dict?("a=1,")).to be(:==, false)
    end
  end

  describe "the frozen value shapes" do
    it "deep-freezes the parse result" do
      list = Fast::SFV.parse_list("(\"a\" b);q=1, c;d=2")
      expect(list).to be(:frozen?)
      expect(list[0]).to be(:frozen?)
      expect(list[0].items).to be(:frozen?)
      expect(list[0].items[0].value).to be(:frozen?)
      expect(list[0].items[1].value).to be(:frozen?)
      expect(list[0].params).to be(:frozen?)
      expect(list[1].params).to be(:frozen?)
      expect(list[1].params.keys.first).to be(:frozen?)

      dictionary = Fast::SFV.parse_dict("en=\"Applepie\", da=:aGVsbG8=:")
      expect(dictionary).to be(:frozen?)
      expect(dictionary.keys.first).to be(:frozen?)
      expect(dictionary["en"].value).to be(:frozen?)
      expect(dictionary["da"].value.encoding).to be(:==, Encoding::ASCII_8BIT)
    end
  end

  describe Fast::SFV::Token do
    it "constructs every grammatical token, the 512-character floor included" do
      %w[FooBar fooBar * *a foo123/456 a_b-c.d3:f%00/*].each do |valid|
        expect(Fast::SFV::Token.new(valid)).to be(:==, valid)
      end
      long = "a" * 512
      expect(Fast::SFV::Token.new(long).length).to be(:==, 512)
    end

    it "raises ArgumentError for content outside the token grammar" do
      ["a b", "a\"b", "", "9foo", "_foo", "-foo", "h\u00e9llo", "a\u0000b"].each do |invalid|
        expect { Fast::SFV::Token.new(invalid) }.to raise_exception(ArgumentError)
      end
    end

    it "raises TypeError for a non-String" do
      [:sym, 42, nil].each do |wrong|
        expect { Fast::SFV::Token.new(wrong) }.to raise_exception(::TypeError)
      end
    end

    it "is a frozen String: content equality both ways, the Hash-key idiom" do
      token = Fast::SFV::Token.new("bar")
      expect(token).to be(:kind_of?, String)
      expect(token.class).to be(:==, Fast::SFV::Token)
      expect(token).to be(:==, "bar")
      expect("bar").to be(:==, token)
      expect({ "bar" => 1 }[Fast::SFV::Token.new("bar")]).to be(:==, 1)
      expect(token.to_s).to be(:==, "bar")
      expect(token.frozen?).to be(:==, true)
      expect { token << "x" }.to raise_exception(FrozenError)
    end

    it "inspects with the class name and the content" do
      text = Fast::SFV::Token.new("bar").inspect
      expect(text.include?("Token")).to be(:==, true)
      expect(text.include?("bar")).to be(:==, true)
    end

    it "goes wherever a String goes: send and JSON" do
      expect("abc".send(Fast::SFV::Token.new("upcase"))).to be(:==, "ABC")
      expect(JSON.generate(Fast::SFV::Token.new("bar"))).to be(:==, "\"bar\"")
    end
  end

  describe "RFC 9651 §3 examples" do
    it "parses Example-List" do
      values = Fast::SFV.parse_list("sugar, tea, rum").map(&:value)
      expect(values).to be(:==, %w[sugar tea rum])
      expect(values.all? { |value| value.is_a?(Fast::SFV::Token) }).to be(:==, true)
    end

    it "parses the inner-list and parameter example" do
      list = Fast::SFV.parse_list("(\"foo\"; a=1;b=2);lvl=5, (\"bar\" \"baz\");lvl=1")
      expect(list[0]).to be(:kind_of?, Fast::SFV::InnerList)
      expect(list[0].items.map(&:value)).to be(:==, ["foo"])
      expect(list[0].items[0].value.is_a?(Fast::SFV::Token)).to be(:==, false)
      expect(list[0].items[0].params).to be(:==, { "a" => 1, "b" => 2 })
      expect(list[0].params).to be(:==, { "lvl" => 5 })
      expect(list[1].items.map(&:value)).to be(:==, %w[bar baz])
      expect(list[1].items.map(&:value).none? { |value| value.is_a?(Fast::SFV::Token) }).to be(:==, true)
    end

    it "parses Example-Dict and Example-IntHeader" do
      dictionary = Fast::SFV.parse_dict("en=\"Applepie\", da=:w4ZibGV0w6ZydGU=:")
      expect(dictionary.keys).to be(:==, %w[en da])
      expect(dictionary["en"].value).to be(:==, "Applepie")
      expect(dictionary["en"].value.is_a?(Fast::SFV::Token)).to be(:==, false)
      expect(dictionary["da"].value.bytes).to be(:==, "Æbletærte".b.bytes)

      integer = Fast::SFV.parse_item("1; a; b=?0")
      expect(integer.value).to be(:==, 1)
      expect(integer.params).to be(:==, { "a" => true, "b" => false })
    end

    it "parses the mixed dictionary example" do
      dictionary = Fast::SFV.parse_dict("a=(1 2), b=3, c=4;aa=bb, d=(5 6);valid")
      expect(dictionary.keys).to be(:==, %w[a b c d])
      expect(dictionary["a"].items.map(&:value)).to be(:==, [1, 2])
      expect(dictionary["b"].value).to be(:==, 3)
      expect(dictionary["c"].params["aa"]).to be(:kind_of?, Fast::SFV::Token)
      expect(dictionary["c"].params).to be(:==, { "aa" => "bb" })
      expect(dictionary["d"].params).to be(:==, { "valid" => true })
    end
  end
end
