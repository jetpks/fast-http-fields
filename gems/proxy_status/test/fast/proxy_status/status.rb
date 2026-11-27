# frozen_string_literal: true

require "fast/proxy_status"

describe Fast::ProxyStatus do
  # The ParseError a strict parse raised, or nil — the frozen offset
  # pins are read off it.
  def strict_error_of(input)
    Fast::ProxyStatus.parse!(input)
    nil
  rescue Fast::ProxyStatus::ParseError => e
    e
  end

  # The SerializeError a construction raised, or nil.
  def serialize_error_of
    yield
    nil
  rescue Fast::ProxyStatus::SerializeError => e
    e
  end

  # The details example of section 2.1.5, its error a quoted String
  # where section 2.1.1 says "a Token" — the erratum vector.
  def details_input
    "proxy.example.net; error=\"http_protocol_error\"; " \
      "details=\"Malformed response header: space before colon\""
  end

  # The details example's canonical re-emit — the RFC writes "; error=" and
  # canonical form is ";error=", the parameter separator with no space.
  def details_canonical
    "proxy.example.net;error=\"http_protocol_error\";" \
      "details=\"Malformed response header: space before colon\""
  end

  describe ".parse" do
    it "reads the section 2 two-intermediary example" do
      field = Fast::ProxyStatus.parse("revproxy1.example.net, ExampleCDN")
      expect(field.size).to be(:==, 2)
      expect(field.first.value).to be(:==, "revproxy1.example.net")
      expect(field.last.value).to be(:==, "ExampleCDN")
      expect(field.first.value).to be(:kind_of?, Fast::SFV::Token)
      expect(field.last.value).to be(:kind_of?, Fast::SFV::Token)
      expect(field.to_s).to be(:==, "revproxy1.example.net, ExampleCDN")
    end

    it "reads the 504 connection_timeout example" do
      field = Fast::ProxyStatus.parse("ExampleCDN; error=connection_timeout")
      expect(field.first.value).to be(:==, "ExampleCDN")
      expect(field.first.error).to be(:==, "connection_timeout")
      expect(field.first.error).to be(:kind_of?, Fast::SFV::Token)
      expect(field.to_s).to be(:==, "ExampleCDN;error=connection_timeout")
    end

    it "reads the 429 http_request_error example" do
      field = Fast::ProxyStatus.parse("r34.example.net; error=http_request_error, ExampleCDN")
      expect(field.size).to be(:==, 2)
      expect(field.first.error).to be(:==, "http_request_error")
      expect(field.last.value).to be(:==, "ExampleCDN")
    end

    it "reads the next-hop example" do
      field = Fast::ProxyStatus.parse("cdn.example.org; next-hop=backend.example.org:8001")
      expect(field.first.next_hop).to be(:==, "backend.example.org:8001")
      expect(field.first.next_hop).to be(:kind_of?, Fast::SFV::Token)
    end

    it "reads the quoted-hop next-protocol example" do
      field = Fast::ProxyStatus.parse("\"proxy.example.org\"; next-protocol=h2")
      expect(field.first.value).to be(:==, "proxy.example.org")
      expect(field.first.value).to be(:instance_of?, String)
      expect(field.first.next_protocol).to be(:==, "h2")
      expect(field.to_s).to be(:==, "\"proxy.example.org\";next-protocol=h2")
    end

    it "reads the received-status example" do
      expect(Fast::ProxyStatus.parse("ExampleCDN; received-status=200").first.received_status).to be(:==, 200)
    end

    it "reads the details example with its quoted error value" do
      field = Fast::ProxyStatus.parse(details_input)
      expect(field.size).to be(:==, 1)
      expect(field.first.error).to be(:==, nil)
      expect(field.first["error"]).to be(:==, "http_protocol_error")
      expect(field.first.details).to be(:==, "Malformed response header: space before colon")
      expect(field.to_s).to be(:==, details_canonical)
    end

    it "preserves unknown parameters in the data and re-emits them" do
      field = Fast::ProxyStatus.parse("ExampleCDN; vendor-x=3, foo;bar=?0")
      expect(field.first["vendor-x"]).to be(:==, 3)
      expect(field.last["bar"]).to be(:==, false)
      expect(field.to_s).to be(:==, "ExampleCDN;vendor-x=3, foo;bar=?0")
    end

    it "preserves wrong-typed parameters with every typed reader nil" do
      field = Fast::ProxyStatus.parse("foo; error=5, bar; received-status=fast, baz; details=?0")
      expect(field.size).to be(:==, 3)
      expect(field.first.error).to be(:==, nil)
      expect(field.first["error"]).to be(:==, 5)
      expect(field[1].received_status).to be(:==, nil)
      expect(field[1]["received-status"]).to be(:==, "fast")
      expect(field[2].details).to be(:==, nil)
      expect(field[2]["details"]).to be(:==, false)
    end

    it "ignores the whole field on a member constraint violation" do
      ["5", "ExampleCDN, 5", "foo, (a b)", "?0", ":AAAA:", "foo, ?1, bar"].each do |bad|
        expect(Fast::ProxyStatus.parse(bad).empty?).to be(:==, true)
        expect(Fast::ProxyStatus.parse(bad).to_s).to be(:==, "")
      end
    end

    it "treats a malformed field as absent, the shared empty value" do
      expect(Fast::ProxyStatus.parse("!!").empty?).to be(:==, true)
      expect(Fast::ProxyStatus.parse("a,").empty?).to be(:==, true)
      expect(Fast::ProxyStatus.parse("!!").to_s).to be(:==, "")
      expect(Fast::ProxyStatus.parse("!!").equal?(Fast::ProxyStatus.parse("5"))).to be(:==, true)
    end

    it "parses the empty field value to a fresh empty value" do
      empty = Fast::ProxyStatus.parse("")
      expect(empty.empty?).to be(:==, true)
      expect(empty.size).to be(:==, 0)
      expect(empty.first).to be(:==, nil)
      expect(empty.to_s).to be(:==, "")
      expect(empty.equal?(Fast::ProxyStatus.parse(""))).to be(:==, false)
      expect(empty == Fast::ProxyStatus.parse("")).to be(:==, true)
    end

    it "combines field lines by concatenation, no last-wins" do
      combined = Fast::ProxyStatus.parse(["foo, bar", "baz"])
      expect(combined.size).to be(:==, 3)
      expect(combined.to_s).to be(:==, "foo, bar, baz")
      expect(Fast::ProxyStatus.parse(%w[foo foo]).size).to be(:==, 2)
    end

    it "raises TypeError for a non-String, non-Array input" do
      [42, nil, 3.14, :sym, {}].each do |wrong|
        expect { Fast::ProxyStatus.parse(wrong) }.to raise_exception(::TypeError)
      end
      expect { Fast::ProxyStatus.parse(["foo", 42]) }.to raise_exception(::TypeError)
    end

    it "answers frozen value objects with frozen members" do
      field = Fast::ProxyStatus.parse(details_input)
      expect(field.frozen?).to be(:==, true)
      expect(field.hops.frozen?).to be(:==, true)
      expect(field.first.frozen?).to be(:==, true)
      expect(field.first.params.frozen?).to be(:==, true)
      expect(field.first.value.frozen?).to be(:==, true)
    end
  end

  describe "the Hop members" do
    it "reads the five typed readers" do
      input = "a; error=x; next-hop=b; next-protocol=h2; received-status=200; details=\"y\""
      hop = Fast::ProxyStatus.parse(input).first
      expect(hop.error).to be(:==, "x")
      expect(hop.error).to be(:kind_of?, Fast::SFV::Token)
      expect(hop.next_hop).to be(:==, "b")
      expect(hop.next_protocol).to be(:==, "h2")
      expect(hop.received_status).to be(:==, 200)
      expect(hop.details).to be(:==, "y")
    end

    it "answers a byte-sequence next-protocol tagged ASCII-8BIT" do
      hop = Fast::ProxyStatus.parse("p; next-protocol=:AAAA:").first
      expect(hop.next_protocol).to be(:==, "\x00\x00\x00".b)
      expect(hop.next_protocol.encoding).to be(:==, Encoding::ASCII_8BIT)
    end

    it "reads a String next-hop and a Token next-protocol" do
      hop = Fast::ProxyStatus.parse("p; next-hop=\"backend three\"; next-protocol=h2").first
      expect(hop.next_hop).to be(:==, "backend three")
      expect(hop.next_hop).to be(:instance_of?, String)
      expect(hop.next_protocol).to be(:kind_of?, Fast::SFV::Token)
    end

    it "is an Item with the raw readers" do
      hop = Fast::ProxyStatus.parse("a; error=x; vendor=1").first
      expect(hop).to be(:kind_of?, Fast::SFV::Item)
      expect(hop.value).to be(:==, "a")
      expect(hop.params["error"]).to be(:==, "x")
      expect(hop["vendor"]).to be(:==, 1)
      expect(hop.to_s).to be(:==, "a;error=x;vendor=1")
    end

    it "compares by canonical form within the Hop class" do
      one = Fast::ProxyStatus.parse("foo;a=1").first
      other = Fast::ProxyStatus.parse("foo; a=1").first
      expect(one == other).to be(:==, true)
      expect(one.eql?(other)).to be(:==, true)
      expect(one.hash).to be(:==, other.hash)
      plain = Fast::SFV::Item.new(Fast::SFV::Token.new("foo"), { "a" => 1 }.freeze)
      expect(one == plain).to be(:==, false)
    end
  end

  describe ".parse!" do
    it "wraps the SFV List failure with its message and offset" do
      error = strict_error_of("!!")
      expect(error).to be(:kind_of?, Fast::ProxyStatus::ParseError)
      expect(error.offset).to be(:==, 0)
      expect(error.message.length).to be(:>, 0)
    end

    it "positions member errors at the identifier, frozen pins" do
      { "5" => 0, "ExampleCDN, 5" => 12, "foo, (a b)" => 5, "foo, :AAAA:" => 5 }.each do |input, offset|
        error = strict_error_of(input)
        expect(error).to be(:kind_of?, Fast::ProxyStatus::ParseError)
        expect(error.offset).to be(:==, offset)
      end
    end

    it "positions parameter errors at the value, frozen pins" do
      pins = {
        "foo; error=5" => 11,
        "foo; error=\"x\"" => 11,
        "foo; error" => 10,
        "foo; received-status=fast" => 21,
        "foo; next-hop=?0" => 14,
        "foo; next-protocol=5" => 19
      }
      pins.each do |input, offset|
        error = strict_error_of(input)
        expect(error).to be(:kind_of?, Fast::ProxyStatus::ParseError)
        expect(error.offset).to be(:==, offset)
      end
    end

    it "combines an Array input before positioning" do
      expect(strict_error_of(["foo; error=5", "bar"]).offset).to be(:==, 11)
    end

    it "positions after a display-string parameter ending in a backslash" do
      # RFC 9651 §4.2.10: a display string's backslash is literal
      # content and only DQUOTE closes, so x=%"\" is a legal parameter
      # value the positioning must cross intact — the later member is
      # raised at its own identifier, never past the field's end.
      expect(strict_error_of(%(a; x=%"\\", 5)).offset).to be(:==, 11)
      expect(strict_error_of(%(a; x=%"\\" , 5)).offset).to be(:==, 12)
      expect(strict_error_of(%(a; x=%"a", 5)).offset).to be(:==, 11)
    end

    it "positions the error parameter after a display-string parameter" do
      # The same §4.2.10 corner in front of the parameter the error
      # names: its VALUE is where the strict parse points, at the
      # parameter's own position — the offsets differ with the OWS
      # around the separators, both pinned.
      expect(strict_error_of(%(a; x=%"\\"; error=3)).offset).to be(:==, 17)
      expect(strict_error_of(%(a; x=%"\\";  error=3)).offset).to be(:==, 18)
    end

    it "positions the section 2.1.5 quoted error at its value" do
      error = strict_error_of("proxy.example.net; error=\"http_protocol_error\"")
      expect(error).to be(:kind_of?, Fast::ProxyStatus::ParseError)
      expect(error.offset).to be(:==, 25)
    end

    it "names the parameter and the type its section states" do
      error = strict_error_of("foo; received-status=fast")
      expect(error.message).to be(:include?, "received-status")
      expect(error.message).to be(:include?, "an Integer")
      erratum = strict_error_of("proxy.example.net; error=\"http_protocol_error\"")
      expect(erratum.message).to be(:include?, "error")
      expect(erratum.message).to be(:include?, "a Token")
    end

    it "raises the first offender in list order" do
      expect(strict_error_of("good; error=5, 5").offset).to be(:==, 12)
      expect(strict_error_of("5, good; error=5").offset).to be(:==, 0)
    end

    it "returns the strict view of a valid field, parameters preserved" do
      field = Fast::ProxyStatus.parse!("ExampleCDN; error=connection_timeout; vendor=1")
      expect(field.first.error).to be(:==, "connection_timeout")
      expect(field.first["vendor"]).to be(:==, 1)
      strict = Fast::ProxyStatus.parse!("r34.example.net; error=http_request_error, ExampleCDN")
      expect(strict.to_s).to be(:==, "r34.example.net;error=http_request_error, ExampleCDN")
      expect(Fast::ProxyStatus.parse!("").empty?).to be(:==, true)
    end

    it "answers an Enumerator from #each without a block" do
      field = Fast::ProxyStatus.parse("revproxy1.example.net, ExampleCDN")
      enumerator = field.each
      expect(enumerator).to be(:kind_of?, ::Enumerator)
      expect(enumerator.to_a.map(&:to_s)).to be(:==, ["revproxy1.example.net", "ExampleCDN"])
      expect(enumerator.each.next.to_s).to be(:==, "revproxy1.example.net")
    end

    it "raises TypeError for a wrong input type, as parse" do
      [42, nil, :sym].each do |wrong|
        expect { Fast::ProxyStatus.parse!(wrong) }.to raise_exception(::TypeError)
      end
    end
  end

  describe ".valid?" do
    it "mirrors the strict parse with a boolean" do
      expect(Fast::ProxyStatus.valid?("revproxy1.example.net, ExampleCDN")).to be(:==, true)
      expect(Fast::ProxyStatus.valid?("ExampleCDN; error=connection_timeout")).to be(:==, true)
      expect(Fast::ProxyStatus.valid?("")).to be(:==, true)
      expect(Fast::ProxyStatus.valid?(["foo", "bar;baz=1"])).to be(:==, true)
      expect(Fast::ProxyStatus.valid?("!!")).to be(:==, false)
      expect(Fast::ProxyStatus.valid?("a,")).to be(:==, false)
      expect(Fast::ProxyStatus.valid?("ExampleCDN, 5")).to be(:==, false)
      expect(Fast::ProxyStatus.valid?("foo; error=5")).to be(:==, false)
      expect(Fast::ProxyStatus.valid?("proxy.example.net; error=\"http_protocol_error\"")).to be(:==, false)
      expect(Fast::ProxyStatus.valid?(5)).to be(:==, false)
      expect(Fast::ProxyStatus.valid?(nil)).to be(:==, false)
    end
  end

  describe ".append" do
    it "appends this intermediary as the last member, the section 2 story" do
      field = Fast::ProxyStatus.append("SomeOtherProxy", Fast::SFV::Token.new("ThisProxy"))
      expect(field.to_s).to be(:==, "SomeOtherProxy, ThisProxy")
      expect(field.size).to be(:==, 2)
      expect(field.first.value).to be(:==, "SomeOtherProxy")
      expect(field.last.value).to be(:==, "ThisProxy")
    end

    it "appends with parameters" do
      field = Fast::ProxyStatus.append(
        "SomeOtherProxy, ThisProxy",
        Fast::SFV::Token.new("ThisProxy"),
        { "error" => Fast::SFV::Token.new("read_timeout") }
      )
      expect(field.to_s).to be(:==, "SomeOtherProxy, ThisProxy, ThisProxy;error=read_timeout")
      expect(field.last.error).to be(:==, "read_timeout")
    end

    it "emits a plain String identifier quoted and a Token bare" do
      expect(Fast::ProxyStatus.append(nil, "My Proxy").to_s).to be(:==, "\"My Proxy\"")
      expect(Fast::ProxyStatus.append(nil, Fast::SFV::Token.new("MyProxy")).to_s).to be(:==, "MyProxy")
    end

    it "starts a fresh list on an absent or unreadable upstream field" do
      expect(Fast::ProxyStatus.append(nil, Fast::SFV::Token.new("MyProxy")).to_s).to be(:==, "MyProxy")
      expect(Fast::ProxyStatus.append("!!", Fast::SFV::Token.new("MyProxy")).to_s).to be(:==, "MyProxy")
      expect(Fast::ProxyStatus.append("5", Fast::SFV::Token.new("MyProxy")).to_s).to be(:==, "MyProxy")
    end

    it "accepts a held value and an Array of field lines" do
      held = Fast::ProxyStatus.parse("a, b")
      expect(Fast::ProxyStatus.append(held, Fast::SFV::Token.new("c")).to_s).to be(:==, "a, b, c")
      expect(Fast::ProxyStatus.append(%w[a b], Fast::SFV::Token.new("c")).to_s).to be(:==, "a, b, c")
    end

    it "re-emits the whole list canonically" do
      field = Fast::ProxyStatus.append("a;x=1 ,  b", Fast::SFV::Token.new("c"))
      expect(field.to_s).to be(:==, "a;x=1, b, c")
    end

    it "never mutates the held value and answers a new frozen value" do
      upstream = Fast::ProxyStatus.parse("a, b")
      appended = upstream.append(Fast::SFV::Token.new("c"))
      expect(upstream.to_s).to be(:==, "a, b")
      expect(appended.to_s).to be(:==, "a, b, c")
      expect(appended.frozen?).to be(:==, true)
    end

    it "raises TypeError for a wrong input, SerializeError for field content" do
      expect { Fast::ProxyStatus.append(5, "x") }.to raise_exception(::TypeError)
      expect(serialize_error_of { Fast::ProxyStatus.append(nil, 5) }).to be(:kind_of?,
                                                                            Fast::ProxyStatus::SerializeError)
      error = serialize_error_of { Fast::ProxyStatus.append(nil, Fast::SFV::Token.new("x"), { "error" => "str" }) }
      expect(error).to be(:kind_of?, Fast::ProxyStatus::SerializeError)
    end
  end

  describe ".promote" do
    it "promotes the section 2 example and removes its trailer" do
      promoted = Fast::ProxyStatus.promote("SomeOtherProxy, ThisProxy", "ThisProxy; error=read_timeout")
      expect(promoted.header.to_s).to be(:==, "SomeOtherProxy, ThisProxy;error=read_timeout")
      expect(promoted.trailer).to be(:==, nil)
    end

    it "keeps an unmatched trailer member in the trailer" do
      promoted = Fast::ProxyStatus.promote("A, B", "C; error=x")
      expect(promoted.header.to_s).to be(:==, "A, B")
      expect(promoted.trailer.to_s).to be(:==, "C;error=x")
    end

    it "replaces the header member in its entirety, parameters included" do
      promoted = Fast::ProxyStatus.promote("ThisProxy;a=1, Other", "ThisProxy")
      expect(promoted.header.to_s).to be(:==, "ThisProxy, Other")
      expect(promoted.trailer).to be(:==, nil)
    end

    it "matches across the String and Token forms" do
      promoted = Fast::ProxyStatus.promote("\"ThisProxy\", Other", "ThisProxy;x=1")
      expect(promoted.header.to_s).to be(:==, "ThisProxy;x=1, Other")
    end

    it "matches the leftmost header member" do
      promoted = Fast::ProxyStatus.promote("A, B, A", "A;x=1")
      expect(promoted.header.to_s).to be(:==, "A;x=1, B, A")
    end

    it "processes trailer members in order against the header as it stands" do
      promoted = Fast::ProxyStatus.promote("A, B", "A;x=1, A;y=2")
      expect(promoted.header.to_s).to be(:==, "A;y=2, B")
      expect(promoted.trailer).to be(:==, nil)
    end

    it "answers header nil exactly when there was no header field" do
      no_header = Fast::ProxyStatus.promote(nil, "A;x=1")
      expect(no_header.header).to be(:==, nil)
      expect(no_header.trailer.to_s).to be(:==, "A;x=1")
      empty_header = Fast::ProxyStatus.promote("", "A;x=1")
      expect(empty_header.header.empty?).to be(:==, true)
      expect(empty_header.trailer.to_s).to be(:==, "A;x=1")
    end

    it "removes an absent or unreadable trailer, leaving the header alone" do
      expect(Fast::ProxyStatus.promote("A, B", nil).trailer).to be(:==, nil)
      unreadable = Fast::ProxyStatus.promote("A, B", "!!")
      expect(unreadable.trailer).to be(:==, nil)
      expect(unreadable.header.to_s).to be(:==, "A, B")
    end

    it "answers both nil for both absent" do
      both = Fast::ProxyStatus.promote(nil, nil)
      expect(both.header).to be(:==, nil)
      expect(both.trailer).to be(:==, nil)
    end

    it "combines lines and uses held values on both sides" do
      lines = Fast::ProxyStatus.promote(%w[SomeOtherProxy ThisProxy], ["ThisProxy; error=read_timeout"])
      expect(lines.header.to_s).to be(:==, "SomeOtherProxy, ThisProxy;error=read_timeout")
      objects = Fast::ProxyStatus.promote(Fast::ProxyStatus.parse("A, B"), Fast::ProxyStatus.parse("B;x=1"))
      expect(objects.header.to_s).to be(:==, "A, B;x=1")
    end

    it "raises TypeError for a wrong input type" do
      expect { Fast::ProxyStatus.promote(5, "A") }.to raise_exception(::TypeError)
      expect { Fast::ProxyStatus.promote("A", 5) }.to raise_exception(::TypeError)
    end

    it "is a frozen value object with class-checked equality" do
      one = Fast::ProxyStatus.promote("A, B", "B;x=1")
      two = Fast::ProxyStatus.promote("A, B", "B;x=1")
      expect(one.frozen?).to be(:==, true)
      expect(one == two).to be(:==, true)
      expect(one.eql?(two)).to be(:==, true)
      expect(one.hash).to be(:==, two.hash)
      expect(one == Fast::ProxyStatus.promote("A, B", "C")).to be(:==, false)
      expect(one == Fast::ProxyStatus.parse("A, B")).to be(:==, false)
    end
  end

  describe "construction" do
    it "emits the member canonically from Hop.new" do
      hop = Fast::ProxyStatus::Hop.new(
        Fast::SFV::Token.new("x"),
        { "error" => Fast::SFV::Token.new("connection_timeout"), "received-status" => 502 }
      )
      expect(hop.to_s).to be(:==, "x;error=connection_timeout;received-status=502")
      field = Fast::ProxyStatus.new([hop])
      expect(field.to_s).to be(:==, "x;error=connection_timeout;received-status=502")
      expect(field.size).to be(:==, 1)
      expect(Fast::ProxyStatus.new([]).to_s).to be(:==, "")
    end

    it "refuses a wrong identifier" do
      [5, nil, "binary".b, true].each do |bad|
        error = serialize_error_of { Fast::ProxyStatus::Hop.new(bad) }
        expect(error).to be(:kind_of?, Fast::ProxyStatus::SerializeError)
      end
    end

    it "refuses a wrong section 2.1 parameter type" do
      wrong = {
        "error" => "str", "received-status" => "200", "details" => Fast::SFV::Token.new("y"),
        "next-protocol" => "h2", "next-hop" => false
      }
      wrong.each_key do |key|
        error = serialize_error_of { Fast::ProxyStatus::Hop.new(Fast::SFV::Token.new("x"), { key => wrong[key] }) }
        expect(error).to be(:kind_of?, Fast::ProxyStatus::SerializeError)
        expect(error.message).to be(:include?, key)
      end
    end

    it "accepts the section 2.1 types and unknown parameters" do
      hop = Fast::ProxyStatus::Hop.new(
        Fast::SFV::Token.new("x"),
        {
          "error" => Fast::SFV::Token.new("dns_error"),
          "next-hop" => Fast::SFV::Token.new("b"),
          "next-protocol" => "\x68\x32".b,
          "received-status" => 502,
          "details" => "d",
          "vendor" => 1.5
        }
      )
      expect(hop.to_s).to be(:==,
                             "x;error=dns_error;next-hop=b;next-protocol=:aDI=:;received-status=502;" \
                             "details=\"d\";vendor=1.5")
      quoted = Fast::ProxyStatus::Hop.new("plain hop", {})
      expect(quoted.to_s).to be(:==, "\"plain hop\"")
    end

    it "refuses parameter keys outside the key grammar" do
      ["Not-A-Key", 5, nil, "with space"].each do |bad|
        error = serialize_error_of { Fast::ProxyStatus::Hop.new(Fast::SFV::Token.new("x"), { bad => 1 }) }
        expect(error).to be(:kind_of?, Fast::ProxyStatus::SerializeError)
      end
    end

    it "refuses non-bare unknown parameter values and non-Hash params" do
      error = serialize_error_of { Fast::ProxyStatus::Hop.new(Fast::SFV::Token.new("x"), { "a" => :sym }) }
      expect(error).to be(:kind_of?, Fast::ProxyStatus::SerializeError)
      expect(serialize_error_of { Fast::ProxyStatus::Hop.new(Fast::SFV::Token.new("x"), 5) })
        .to be(:kind_of?, Fast::ProxyStatus::SerializeError)
    end

    it "refuses members that are not Hops" do
      expect(serialize_error_of { Fast::ProxyStatus.new("foo") }).to be(:kind_of?,
                                                                        Fast::ProxyStatus::SerializeError)
      expect(serialize_error_of { Fast::ProxyStatus.new(["foo"]) }).to be(:kind_of?,
                                                                          Fast::ProxyStatus::SerializeError)
    end

    it "freezes the value and params in place" do
      value = "hop".dup
      params = { "a" => 1 }
      built = Fast::ProxyStatus::Hop.new(value, params)
      expect(built.frozen?).to be(:==, true)
      expect(value.frozen?).to be(:==, true)
      expect(params.frozen?).to be(:==, true)
    end
  end

  describe "to_s" do
    it "canonicalizes spacing" do
      expect(Fast::ProxyStatus.parse("a ,  b").to_s).to be(:==, "a, b")
      canonical = Fast::ProxyStatus.parse("ExampleCDN; error=connection_timeout").to_s
      expect(canonical).to be(:==, "ExampleCDN;error=connection_timeout")
    end

    it "round-trips parse through emit" do
      input = "revproxy1.example.net, ExampleCDN, \"quoted hop\";details=\"d\""
      expect(Fast::ProxyStatus.parse(input).to_s).to be(:==, input)
    end
  end

  describe "equality" do
    it "compares by canonical wire form within the class" do
      one = Fast::ProxyStatus.parse("revproxy1.example.net, ExampleCDN")
      other = Fast::ProxyStatus.parse("revproxy1.example.net , ExampleCDN")
      expect(one == other).to be(:==, true)
      expect(one.eql?(other)).to be(:==, true)
      expect(one.hash).to be(:==, other.hash)
      expect(one == Fast::ProxyStatus.parse("revproxy1.example.net")).to be(:==, false)
      expect(one == "revproxy1.example.net, ExampleCDN").to be(:==, false)
    end

    it "inspects with the class name and the wire form" do
      expect(Fast::ProxyStatus.parse("ExampleCDN; error=connection_timeout").inspect)
        .to be(:==, "#<Fast::ProxyStatus ExampleCDN;error=connection_timeout>")
      expect(Fast::ProxyStatus.parse("").inspect).to be(:==, "#<Fast::ProxyStatus>")
    end
  end
end
