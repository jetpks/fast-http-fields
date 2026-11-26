# frozen_string_literal: true

require "fast/proxy_status"

describe Fast::CacheStatus do
  # The ParseError a strict parse raised, or nil — the frozen offset
  # pins are read off it.
  def strict_error_of(input)
    Fast::CacheStatus.parse!(input)
    nil
  rescue Fast::CacheStatus::ParseError => e
    e
  end

  # The SerializeError a construction raised, or nil.
  def serialize_error_of
    yield
    nil
  rescue Fast::CacheStatus::SerializeError => e
    e
  end

  # The section 3 two-layer example, with its quoted-String second
  # identifier — the member constraint's two wire forms in one field.
  def two_layer
    'OriginCache; hit; ttl=1100, "CDN Company Here"; hit; ttl=545'
  end

  # The section 3 three-layer example: three field lines, combined per
  # RFC 9651 §4.2 — a List concatenates, no last-wins.
  def three_lines
    ["ReverseProxyCache; hit", "ForwardProxyCache; fwd=uri-miss; collapsed; stored", "BrowserCache; fwd=uri-miss"]
  end

  describe ".parse" do
    it "reads the section 3 minimal hit example" do
      field = Fast::CacheStatus.parse("ExampleCache; hit")
      expect(field.size).to be(:==, 1)
      expect(field.first.value).to be(:==, "ExampleCache")
      expect(field.first.value).to be(:kind_of?, Fast::SFV::Token)
      expect(field.first.hit).to be(:==, true)
      expect(field.to_s).to be(:==, "ExampleCache;hit")
    end

    it "reads the polite hit with its ttl" do
      field = Fast::CacheStatus.parse("ExampleCache; hit; ttl=376")
      expect(field.first.hit).to be(:==, true)
      expect(field.first.ttl).to be(:==, 376)
      expect(field.to_s).to be(:==, "ExampleCache;hit;ttl=376")
    end

    it "reads the stale hit with a negative ttl" do
      field = Fast::CacheStatus.parse("ExampleCache; hit; ttl=-412")
      expect(field.first.ttl).to be(:==, -412)
      expect(field.to_s).to be(:==, "ExampleCache;hit;ttl=-412")
    end

    it "reads the complete miss example" do
      field = Fast::CacheStatus.parse("ExampleCache; fwd=uri-miss")
      expect(field.first.fwd).to be(:==, "uri-miss")
      expect(field.first.fwd).to be(:kind_of?, Fast::SFV::Token)
      expect(field.first.hit).to be(:==, nil)
    end

    it "reads the miss that successfully validated" do
      field = Fast::CacheStatus.parse("ExampleCache; fwd=stale; fwd-status=304")
      expect(field.first.fwd).to be(:==, "stale")
      expect(field.first.fwd_status).to be(:==, 304)
    end

    it "reads the collapsed miss and the failed collapse" do
      collapsed = Fast::CacheStatus.parse("ExampleCache; fwd=uri-miss; collapsed")
      expect(collapsed.first.collapsed).to be(:==, true)
      expect(collapsed.first.stored).to be(:==, nil)
      failed = Fast::CacheStatus.parse("ExampleCache; fwd=uri-miss; collapsed=?0")
      expect(failed.first.collapsed).to be(:==, false)
      expect(failed.to_s).to be(:==, "ExampleCache;fwd=uri-miss;collapsed=?0")
    end

    it "reads the section 2.8 detail example with a Token value" do
      field = Fast::CacheStatus.parse("ExampleCache; hit; detail=MEMORY")
      expect(field.first.detail).to be(:==, "MEMORY")
      expect(field.first.detail).to be(:kind_of?, Fast::SFV::Token)
    end

    it "reads the two-layer example with its quoted-String identifier" do
      field = Fast::CacheStatus.parse(two_layer)
      expect(field.size).to be(:==, 2)
      expect(field.first.value).to be(:==, "OriginCache")
      expect(field.first.value).to be(:kind_of?, Fast::SFV::Token)
      expect(field.last.value).to be(:==, "CDN Company Here")
      expect(field.last.value).to be(:instance_of?, String)
      expect(field.last.ttl).to be(:==, 545)
      expect(field.to_s).to be(:==, 'OriginCache;hit;ttl=1100, "CDN Company Here";hit;ttl=545')
    end

    it "combines the three-line example, a List concatenates" do
      field = Fast::CacheStatus.parse(three_lines)
      expect(field.size).to be(:==, 3)
      expect(field.caches.map(&:value)).to be(:==, %w[ReverseProxyCache ForwardProxyCache BrowserCache])
      expect(field.first.hit).to be(:==, true)
      expect(field[1].fwd).to be(:==, "uri-miss")
      expect(field[1].collapsed).to be(:==, true)
      expect(field[1].stored).to be(:==, true)
      expect(field.last.fwd).to be(:==, "uri-miss")
      expect(field.to_s).to be(:==,
                               "ReverseProxyCache;hit, ForwardProxyCache;fwd=uri-miss;collapsed;stored, " \
                               "BrowserCache;fwd=uri-miss")
    end

    it "reads a String key parameter" do
      field = Fast::CacheStatus.parse('ExampleCache; hit; key="v2/user/1234"')
      expect(field.first.key).to be(:==, "v2/user/1234")
    end

    it "preserves unknown parameters in the data and re-emits them" do
      field = Fast::CacheStatus.parse("ExampleCache; hit; vendor-x=3, foo;bar=?0")
      expect(field.first["vendor-x"]).to be(:==, 3)
      expect(field.last["bar"]).to be(:==, false)
      expect(field.to_s).to be(:==, "ExampleCache;hit;vendor-x=3, foo;bar=?0")
    end

    it "preserves wrong-typed parameters with every typed reader nil" do
      field = Fast::CacheStatus.parse("ExampleCache; fwd=999, Second; hit=\"yes\", Third; ttl=fast")
      expect(field.size).to be(:==, 3)
      expect(field.first.fwd).to be(:==, nil)
      expect(field.first["fwd"]).to be(:==, 999)
      expect(field[1].hit).to be(:==, nil)
      expect(field[1]["hit"]).to be(:==, "yes")
      expect(field[2].ttl).to be(:==, nil)
      expect(field[2]["ttl"]).to be(:==, "fast")
      expect(field.to_s).to be(:==, 'ExampleCache;fwd=999, Second;hit="yes", Third;ttl=fast')
    end

    it "ignores the whole field on a member constraint violation" do
      ["5", "ExampleCache, 5", "foo, (a b)", "?0", ":AAAA:", "foo, ?1, bar"].each do |bad|
        expect(Fast::CacheStatus.parse(bad).empty?).to be(:==, true)
        expect(Fast::CacheStatus.parse(bad).to_s).to be(:==, "")
      end
    end

    it "treats a malformed field as absent, the shared empty value" do
      expect(Fast::CacheStatus.parse("!!").empty?).to be(:==, true)
      expect(Fast::CacheStatus.parse("a,").empty?).to be(:==, true)
      expect(Fast::CacheStatus.parse("!!").to_s).to be(:==, "")
      expect(Fast::CacheStatus.parse("!!").equal?(Fast::CacheStatus.parse("5"))).to be(:==, true)
    end

    it "parses the empty field value to a fresh empty value" do
      empty = Fast::CacheStatus.parse("")
      expect(empty.empty?).to be(:==, true)
      expect(empty.size).to be(:==, 0)
      expect(empty.first).to be(:==, nil)
      expect(empty.to_s).to be(:==, "")
      expect(empty.equal?(Fast::CacheStatus.parse(""))).to be(:==, false)
      expect(empty == Fast::CacheStatus.parse("")).to be(:==, true)
    end

    it "combines field lines by concatenation, no last-wins" do
      combined = Fast::CacheStatus.parse(["foo; hit", "bar; fwd=miss"])
      expect(combined.size).to be(:==, 2)
      expect(Fast::CacheStatus.parse(["foo; hit", "foo; hit"]).size).to be(:==, 2)
    end

    it "raises TypeError for a non-String, non-Array input" do
      [42, nil, 3.14, :sym, {}].each do |wrong|
        expect { Fast::CacheStatus.parse(wrong) }.to raise_exception(::TypeError)
      end
      expect { Fast::CacheStatus.parse(["foo", 42]) }.to raise_exception(::TypeError)
    end

    it "answers frozen value objects with frozen members" do
      field = Fast::CacheStatus.parse(two_layer)
      expect(field.frozen?).to be(:==, true)
      expect(field.caches.frozen?).to be(:==, true)
      expect(field.first.frozen?).to be(:==, true)
      expect(field.first.params.frozen?).to be(:==, true)
      expect(field.first.value.frozen?).to be(:==, true)
    end
  end

  describe "the Cache members" do
    it "reads the eight typed readers" do
      input = 'c; hit; fwd=miss; fwd-status=304; ttl=1100; stored; collapsed; key="k"; detail="d"'
      cache = Fast::CacheStatus.parse(input).first
      expect(cache.hit).to be(:==, true)
      expect(cache.fwd).to be(:==, "miss")
      expect(cache.fwd_status).to be(:==, 304)
      expect(cache.ttl).to be(:==, 1100)
      expect(cache.stored).to be(:==, true)
      expect(cache.collapsed).to be(:==, true)
      expect(cache.key).to be(:==, "k")
      expect(cache.detail).to be(:==, "d")
    end

    it "answers nil for a wrong-typed or absent parameter" do
      cache = Fast::CacheStatus.parse("c; fwd=999; hit=\"yes\"; key=MEMORY; detail=5").first
      expect(cache.fwd).to be(:==, nil)
      expect(cache.hit).to be(:==, nil)
      expect(cache.key).to be(:==, nil)
      expect(cache.detail).to be(:==, nil)
      expect(cache.ttl).to be(:==, nil)
      expect(cache.stored).to be(:==, nil)
      expect(cache.collapsed).to be(:==, nil)
      expect(cache.fwd_status).to be(:==, nil)
    end

    it "answers false for a present Boolean, a value never an absence" do
      cache = Fast::CacheStatus.parse("c; hit=?0; stored=?0; collapsed=?0").first
      expect(cache.hit).to be(:==, false)
      expect(cache.stored).to be(:==, false)
      expect(cache.collapsed).to be(:==, false)
    end

    it "answers a Token detail beside a String detail" do
      field = Fast::CacheStatus.parse('c; detail=MEMORY, d; detail="in core"')
      expect(field.first.detail).to be(:kind_of?, Fast::SFV::Token)
      expect(field[1].detail).to be(:instance_of?, String)
    end

    it "is an Item with the raw readers" do
      cache = Fast::CacheStatus.parse("a; hit; vendor=1").first
      expect(cache).to be(:kind_of?, Fast::SFV::Item)
      expect(cache.value).to be(:==, "a")
      expect(cache.params["hit"]).to be(:==, true)
      expect(cache["vendor"]).to be(:==, 1)
      expect(cache.to_s).to be(:==, "a;hit;vendor=1")
    end

    it "surfaces the hit/fwd exclusivity SHOULD without gating anything" do
      both = Fast::CacheStatus.parse("ExampleCache; hit; fwd=miss").first
      expect(both.hit_and_fwd?).to be(:==, true)
      expect(Fast::CacheStatus.parse("ExampleCache; hit=?0; fwd=miss").first.hit_and_fwd?).to be(:==, true)
      expect(Fast::CacheStatus.parse("ExampleCache; hit").first.hit_and_fwd?).to be(:==, false)
      expect(Fast::CacheStatus.parse("ExampleCache; fwd=miss").first.hit_and_fwd?).to be(:==, false)
    end

    it "compares by canonical form within the Cache class" do
      one = Fast::CacheStatus.parse("foo;hit").first
      other = Fast::CacheStatus.parse("foo; hit").first
      expect(one == other).to be(:==, true)
      expect(one.eql?(other)).to be(:==, true)
      expect(one.hash).to be(:==, other.hash)
      plain = Fast::SFV::Item.new(Fast::SFV::Token.new("foo"), { "hit" => true }.freeze)
      expect(one == plain).to be(:==, false)
      expect(one == Fast::ProxyStatus.parse("foo;error=x").first).to be(:==, false)
    end

    it "carries the eight sections' parameters and the fwd set as frozen data" do
      expected = {
        "hit" => "a Boolean", "fwd" => "a Token", "fwd-status" => "an Integer", "ttl" => "an Integer",
        "stored" => "a Boolean", "collapsed" => "a Boolean", "key" => "a String", "detail" => "a String or Token"
      }
      fwd = %w[bypass method uri-miss vary-miss miss request stale partial]
      expect(Fast::CacheStatus::PARAMETERS).to be(:==, expected)
      expect(Fast::CacheStatus::PARAMETERS.frozen?).to be(:==, true)
      expect(Fast::CacheStatus::PARAMETERS.size).to be(:==, 8)
      expect(Fast::CacheStatus::FWD).to be(:==, fwd)
      expect(Fast::CacheStatus::FWD.frozen?).to be(:==, true)
    end

    it "never gates a parse on the tables: an unregistered fwd Token round-trips" do
      field = Fast::CacheStatus.parse("ExampleCache; vendor-x=3; fwd=network-miss")
      expect(field.first.fwd).to be(:==, "network-miss")
      expect(field.to_s).to be(:==, "ExampleCache;vendor-x=3;fwd=network-miss")
    end
  end

  describe ".parse!" do
    it "wraps the SFV List failure with its message and offset" do
      error = strict_error_of("!!")
      expect(error).to be(:kind_of?, Fast::CacheStatus::ParseError)
      expect(error.offset).to be(:==, 0)
      expect(error.message.length).to be(:>, 0)
    end

    it "positions member errors at the identifier, frozen pins" do
      { "5" => 0, "ExampleCache, 5" => 14, "foo, (a b)" => 5, "foo, :AAAA:" => 5 }.each do |input, offset|
        error = strict_error_of(input)
        expect(error).to be(:kind_of?, Fast::CacheStatus::ParseError)
        expect(error.offset).to be(:==, offset)
      end
    end

    it "positions parameter errors at the value, frozen pins" do
      pins = {
        "foo; fwd=999" => 9, "foo; hit=1" => 9, "foo; fwd-status=fast" => 16, "foo; ttl=1.5" => 9,
        "foo; collapsed=miss" => 15, "foo; key=MEMORY" => 9, "foo; stored=x" => 12, "foo; detail=1" => 12
      }
      pins.each do |input, offset|
        error = strict_error_of(input)
        expect(error).to be(:kind_of?, Fast::CacheStatus::ParseError)
        expect(error.offset).to be(:==, offset)
      end
    end

    it "combines an Array input before positioning" do
      expect(strict_error_of(["foo; fwd=999", "bar"]).offset).to be(:==, 9)
    end

    it "raises the first offender in list order" do
      expect(strict_error_of("good; fwd=999, 5").offset).to be(:==, 10)
      expect(strict_error_of("5, good; fwd=999").offset).to be(:==, 0)
    end

    it "names the parameter and the type its section states" do
      error = strict_error_of("foo; ttl=1.5")
      expect(error.message).to be(:include?, "ttl")
      expect(error.message).to be(:include?, "an Integer")
      fwd_error = strict_error_of("foo; fwd=999")
      expect(fwd_error.message).to be(:include?, "a Token")
    end

    it "returns the strict view of a valid field, parameters preserved" do
      field = Fast::CacheStatus.parse!("ExampleCache; fwd=uri-miss; vendor=1")
      expect(field.first.fwd).to be(:==, "uri-miss")
      expect(field.first["vendor"]).to be(:==, 1)
      strict = Fast::CacheStatus.parse!(two_layer)
      expect(strict.to_s).to be(:==, 'OriginCache;hit;ttl=1100, "CDN Company Here";hit;ttl=545')
      expect(Fast::CacheStatus.parse!("").empty?).to be(:==, true)
    end

    it "raises TypeError for a wrong input type, as parse" do
      [42, nil, :sym].each do |wrong|
        expect { Fast::CacheStatus.parse!(wrong) }.to raise_exception(::TypeError)
      end
    end
  end

  describe ".valid?" do
    it "mirrors the strict parse with a boolean" do
      expect(Fast::CacheStatus.valid?("ExampleCache; hit; ttl=376")).to be(:==, true)
      expect(Fast::CacheStatus.valid?(two_layer)).to be(:==, true)
      expect(Fast::CacheStatus.valid?(three_lines)).to be(:==, true)
      expect(Fast::CacheStatus.valid?("")).to be(:==, true)
      expect(Fast::CacheStatus.valid?("ExampleCache; hit; fwd=miss")).to be(:==, true)
      expect(Fast::CacheStatus.valid?("ExampleCache; fwd=network-miss")).to be(:==, true)
      expect(Fast::CacheStatus.valid?("!!")).to be(:==, false)
      expect(Fast::CacheStatus.valid?("ExampleCache, 5")).to be(:==, false)
      expect(Fast::CacheStatus.valid?("foo; fwd=999")).to be(:==, false)
      expect(Fast::CacheStatus.valid?("foo; ttl=fast")).to be(:==, false)
      expect(Fast::CacheStatus.valid?(5)).to be(:==, false)
      expect(Fast::CacheStatus.valid?(nil)).to be(:==, false)
    end
  end

  describe ".append" do
    it "appends this cache as the last member, the section 2 story" do
      appended = Fast::CacheStatus.append(two_layer, Fast::SFV::Token.new("MyCache"),
                                          { "fwd" => Fast::SFV::Token.new("miss") })
      expect(appended.size).to be(:==, 3)
      expect(appended.first.value).to be(:==, "OriginCache")
      expect(appended.last.value).to be(:==, "MyCache")
      expect(appended.to_s).to be(:==,
                                  'OriginCache;hit;ttl=1100, "CDN Company Here";hit;ttl=545, MyCache;fwd=miss')
    end

    it "emits a plain String identifier quoted and a Token bare" do
      expect(Fast::CacheStatus.append(nil, "My Cache").to_s).to be(:==, '"My Cache"')
      expect(Fast::CacheStatus.append(nil, Fast::SFV::Token.new("MyCache")).to_s).to be(:==, "MyCache")
    end

    it "starts a fresh list on an absent or unreadable upstream field" do
      expect(Fast::CacheStatus.append(nil, Fast::SFV::Token.new("MyCache")).to_s).to be(:==, "MyCache")
      expect(Fast::CacheStatus.append("!!", Fast::SFV::Token.new("MyCache")).to_s).to be(:==, "MyCache")
      expect(Fast::CacheStatus.append("5", Fast::SFV::Token.new("MyCache")).to_s).to be(:==, "MyCache")
    end

    it "accepts a held value and an Array of field lines" do
      held = Fast::CacheStatus.parse("a; hit")
      expect(Fast::CacheStatus.append(held, Fast::SFV::Token.new("c")).to_s).to be(:==, "a;hit, c")
      expect(Fast::CacheStatus.append(["a; hit", "b; hit"], Fast::SFV::Token.new("c")).size).to be(:==, 3)
    end

    it "re-emits the whole list canonically" do
      field = Fast::CacheStatus.append("a;hit=1 ,  b", Fast::SFV::Token.new("c"))
      expect(field.to_s).to be(:==, "a;hit=1, b, c")
    end

    it "never mutates the held value and answers a new frozen value" do
      upstream = Fast::CacheStatus.parse("a; hit")
      appended = upstream.append(Fast::SFV::Token.new("c"))
      expect(upstream.to_s).to be(:==, "a;hit")
      expect(appended.to_s).to be(:==, "a;hit, c")
      expect(appended.frozen?).to be(:==, true)
    end

    it "raises TypeError for a wrong input, SerializeError for field content" do
      expect { Fast::CacheStatus.append(5, "x") }.to raise_exception(::TypeError)
      expect(serialize_error_of { Fast::CacheStatus.append(nil, 5) }).to be(:kind_of?,
                                                                            Fast::CacheStatus::SerializeError)
      error = serialize_error_of { Fast::CacheStatus.append(nil, "x", { "fwd" => Fast::SFV::Token.new("weird") }) }
      expect(error).to be(:kind_of?, Fast::CacheStatus::SerializeError)
    end
  end

  describe "construction" do
    it "emits the member canonically from Cache.new" do
      cache = Fast::CacheStatus::Cache.new(
        Fast::SFV::Token.new("x"),
        { "hit" => true, "ttl" => 376 }
      )
      expect(cache.to_s).to be(:==, "x;hit;ttl=376")
      field = Fast::CacheStatus.new([cache])
      expect(field.to_s).to be(:==, "x;hit;ttl=376")
      expect(field.size).to be(:==, 1)
      expect(Fast::CacheStatus.new([]).to_s).to be(:==, "")
    end

    it "refuses a wrong identifier" do
      [5, nil, "binary".b, true].each do |bad|
        error = serialize_error_of { Fast::CacheStatus::Cache.new(bad) }
        expect(error).to be(:kind_of?, Fast::CacheStatus::SerializeError)
      end
    end

    it "refuses a wrong section 2.1-2.8 parameter type" do
      # An Array of pairs, not a Hash literal: a literal with repeated
      # keys collapses to the last pair silently.
      wrong = [
        ["hit", 1], %w[fwd str], %w[fwd-status 200], ["ttl", 1.5], ["stored", 1], %w[collapsed miss],
        ["key", Fast::SFV::Token.new("k")], ["detail", 5]
      ]
      wrong.each do |key, value|
        error = serialize_error_of { Fast::CacheStatus::Cache.new(Fast::SFV::Token.new("x"), { key => value }) }
        expect(error).to be(:kind_of?, Fast::CacheStatus::SerializeError)
        expect(error.message).to be(:include?, key)
      end
    end

    it "validates fwd against the section 2.2 set on emit only" do
      weird = { "fwd" => Fast::SFV::Token.new("weird") }
      error = serialize_error_of { Fast::CacheStatus::Cache.new(Fast::SFV::Token.new("x"), weird) }
      expect(error).to be(:kind_of?, Fast::CacheStatus::SerializeError)
      expect(error.message).to be(:include?, "fwd")
      expect(error.message).to be(:include?, "bypass")
      Fast::CacheStatus::FWD.each do |value|
        built = Fast::CacheStatus::Cache.new(Fast::SFV::Token.new("x"), { "fwd" => Fast::SFV::Token.new(value) })
        expect(built.fwd).to be(:==, value)
      end
      expect(Fast::CacheStatus.parse("ExampleCache; fwd=network-miss").first.fwd).to be(:==, "network-miss")
    end

    it "accepts the section 2.1-2.8 types and unknown parameters" do
      cache = Fast::CacheStatus::Cache.new(
        Fast::SFV::Token.new("x"),
        {
          "hit" => true, "fwd" => Fast::SFV::Token.new("miss"), "fwd-status" => 304, "ttl" => -412,
          "stored" => false, "collapsed" => true, "key" => "k", "detail" => Fast::SFV::Token.new("MEMORY"),
          "vendor" => 1.5
        }
      )
      expect(cache.to_s).to be(:==,
                               "x;hit;fwd=miss;fwd-status=304;ttl=-412;stored=?0;collapsed;key=\"k\";" \
                               "detail=MEMORY;vendor=1.5")
      quoted = Fast::CacheStatus::Cache.new("My Cache", {})
      expect(quoted.to_s).to be(:==, '"My Cache"')
    end

    it "refuses parameter keys outside the key grammar and non-Hash params" do
      ["Not-A-Key", 5, nil, "with space"].each do |bad|
        error = serialize_error_of { Fast::CacheStatus::Cache.new(Fast::SFV::Token.new("x"), { bad => 1 }) }
        expect(error).to be(:kind_of?, Fast::CacheStatus::SerializeError)
      end
      expect(serialize_error_of { Fast::CacheStatus::Cache.new(Fast::SFV::Token.new("x"), 5) })
        .to be(:kind_of?, Fast::CacheStatus::SerializeError)
    end

    it "refuses non-bare unknown parameter values" do
      error = serialize_error_of { Fast::CacheStatus::Cache.new(Fast::SFV::Token.new("x"), { "a" => :sym }) }
      expect(error).to be(:kind_of?, Fast::CacheStatus::SerializeError)
    end

    it "refuses members that are not Caches" do
      expect(serialize_error_of { Fast::CacheStatus.new("foo") }).to be(:kind_of?,
                                                                        Fast::CacheStatus::SerializeError)
      expect(serialize_error_of { Fast::CacheStatus.new(["foo"]) }).to be(:kind_of?,
                                                                          Fast::CacheStatus::SerializeError)
      expect(serialize_error_of { Fast::CacheStatus.new([Fast::ProxyStatus.parse("a").first]) })
        .to be(:kind_of?, Fast::CacheStatus::SerializeError)
    end

    it "freezes the value and params in place" do
      value = "cache".dup
      params = { "a" => 1 }
      built = Fast::CacheStatus::Cache.new(value, params)
      expect(built.frozen?).to be(:==, true)
      expect(value.frozen?).to be(:==, true)
      expect(params.frozen?).to be(:==, true)
      members = [built]
      field = Fast::CacheStatus.new(members)
      expect(field.frozen?).to be(:==, true)
      expect(members.frozen?).to be(:==, true)
    end
  end

  describe "to_s" do
    it "canonicalizes spacing" do
      expect(Fast::CacheStatus.parse("a ,  b").to_s).to be(:==, "a, b")
      canonical = Fast::CacheStatus.parse("ExampleCache; hit; ttl=376").to_s
      expect(canonical).to be(:==, "ExampleCache;hit;ttl=376")
    end

    it "round-trips parse through emit" do
      inputs = [
        "ExampleCache;hit", "ExampleCache;hit;ttl=376", "ExampleCache;hit;ttl=-412", "ExampleCache;fwd=uri-miss",
        "ExampleCache;fwd=stale;fwd-status=304", "ExampleCache;fwd=uri-miss;collapsed",
        "ExampleCache;fwd=uri-miss;collapsed=?0", 'OriginCache;hit;ttl=1100, "CDN Company Here";hit;ttl=545'
      ]
      inputs.each do |wire|
        expect(Fast::CacheStatus.parse(wire).to_s).to be(:==, wire)
      end
    end
  end

  describe "the error hierarchy" do
    it "descends from the gem root with both error shapes carrying offset" do
      expect(Fast::CacheStatus::Error < Fast::ProxyStatus::Error).to be(:==, true)
      expect(Fast::CacheStatus::ParseError < Fast::CacheStatus::Error).to be(:==, true)
      expect(Fast::CacheStatus::SerializeError < Fast::CacheStatus::Error).to be(:==, true)
      expect(Fast::CacheStatus::ParseError.new("message", 7).offset).to be(:==, 7)
      expect(Fast::CacheStatus::SerializeError.new("message", 0).offset).to be(:==, 0)
    end

    it "is guarded by one rescue on the gem root" do
      begin
        raise Fast::CacheStatus::ParseError.new("x", 0)
      rescue Fast::ProxyStatus::Error
        guarded = true
      end
      expect(guarded).to be(:==, true)
    end
  end

  describe "equality" do
    it "compares by canonical wire form within the class" do
      one = Fast::CacheStatus.parse(two_layer)
      other = Fast::CacheStatus.parse('OriginCache; hit; ttl=1100 , "CDN Company Here"; hit; ttl=545')
      expect(one == other).to be(:==, true)
      expect(one.eql?(other)).to be(:==, true)
      expect(one.hash).to be(:==, other.hash)
      expect(one == Fast::CacheStatus.parse("OriginCache;hit;ttl=1100")).to be(:==, false)
      expect(one == two_layer).to be(:==, false)
      expect(one == Fast::ProxyStatus.parse("a, b")).to be(:==, false)
    end

    it "inspects with the class name and the wire form" do
      expect(Fast::CacheStatus.parse("ExampleCache; hit; ttl=376").inspect)
        .to be(:==, "#<Fast::CacheStatus ExampleCache;hit;ttl=376>")
      expect(Fast::CacheStatus.parse("").inspect).to be(:==, "#<Fast::CacheStatus>")
    end
  end
end
