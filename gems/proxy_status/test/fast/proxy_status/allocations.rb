# frozen_string_literal: true

require "fast/proxy_status"

# Allocation budgets for the ten Proxy-Status paths and the seventeen
# Cache-Status and TargetedCacheControl paths: what one operation
# costs in Ruby objects beyond the input. Counts are GC.stat,
# averaged over runs so a one-off allocation outside the block
# (GC.stat's own, under coverage) does not count, and everything a
# measured block touches is a local. Measured on Ruby 4.0.10, then
# frozen: the two-member parse
# of the section 2 example 13 (the Fast::SFV Parser, its two Tokens
# with their content slices, the two Items, the Hops the member walk
# builds, the mapped Array and the frozen value object); the malformed
# fall to the shared frozen empty value 8 (the SFV parse's own failure
# path — its message String, its ParseError and the backtrace — plus
# the wrapped ParseError; the empty value itself is shared and costs
# nothing); the member-violation fall 11 (the parse's six, then the
# positioning Scan with its walk and the raised, positioned ParseError
# — the one path that pays for offsets, since the lenient policy is
# the strict walk with the section 2.1 checks off, the member failure
# rescued into the empty value); the strict parse 13 and the valid?
# mirror 13 (the clean paths count alike — the Scan runs only where an
# error needs an offset); the Hop construction 2 (the default params
# Hash and the frozen Hop); the append on a held value 4 (the members
# copy, the params Hash, the Hop, the value object — no re-parse, no
# re-emit); the append over a received String 17 (the lenient parse
# 13, then the held append's four); the promote of the section 2
# example 30 (two lenient parses, the header copy, the
# remaining-members Array, the two value objects and the frozen
# Promotion); the emit 1 (the output String, whatever the member
# count).
#
# Cache-Status, measured the same way and frozen: the two-layer
# section 3 parse 17 (the SFV Parser, the Token and the quoted String,
# the four parameter values, the two Items, the two Caches, the mapped
# Array and the frozen value object); the three-line combined parse
# 32 (three members, the combined String the Array join builds, and
# the parse's own count over them); the malformed fall 8; the
# member-violation fall 11 (the positioning Scan's price, as the
# Proxy-Status path pays it); the strict parse 11 and the valid?
# mirror 17 (the Scan runs only on the error path, so the clean paths
# count the parse's own); the Cache construction 2 (the default params
# Hash and the frozen Cache); the append on a held value 4 (the members
# copy, the params Hash, the Cache, the value object); the append over
# a received String 15 (the lenient parse 11, then the held append's
# four); the emit 1.
#
# TargetedCacheControl, measured the same way and frozen: the
# two-member parse 9 (the SFV Parser, the dictionary Hash with its two
# key slices and two Items, the violations Array, the keys view and
# the frozen value object); the malformed fall 8; the flagged parse 8
# (the parse's own count plus the key the walk flags — the flag is
# data, never a wire change); the strict parse 9 and the valid? mirror
# 9 (the dict Scan runs only where an error needs an offset); the
# construction 5 (the held Hash, the Item, the violations Array, the
# keys view and the frozen value object); the emit 1.
#
# The counts are the machine's and the implementation's — the budget
# bounds below freeze this measurement, an honest ceiling per path.
describe "allocations" do
  # Objects allocated per run of the block, averaged over +times+ runs.
  def allocations(times = 100, &block)
    before = GC.stat(:total_allocated_objects)
    times.times(&block)
    (GC.stat(:total_allocated_objects) - before) / times.to_f
  end

  it "parses the section 2 two-member example in thirteen objects" do
    input = "revproxy1.example.net, ExampleCDN"
    Fast::ProxyStatus.parse(input)
    # The SFV Parser, two Tokens with their slices, two Items, two
    # Hops, the mapped Array, the frozen value object.
    expect(allocations { Fast::ProxyStatus.parse(input) }).to be(:<, 14)
  end

  it "falls to the shared empty value on a malformed field in eight objects" do
    Fast::ProxyStatus.parse("!!")
    # The SFV parse's failure path (message, ParseError, backtrace) and
    # the wrapped ParseError; the empty value is shared and free.
    expect(allocations { Fast::ProxyStatus.parse("!!") }).to be(:<, 9)
  end

  it "pays the positioning Scan on a member-violation fall in eleven objects" do
    Fast::ProxyStatus.parse("ExampleCDN, 5")
    # The parse's six, the Scan instance, the positioned ParseError and
    # its message — the member failure the lenient parse rescues.
    expect(allocations { Fast::ProxyStatus.parse("ExampleCDN, 5") }).to be(:<, 12)
  end

  it "parses strictly in thirteen objects" do
    input = "revproxy1.example.net, ExampleCDN"
    Fast::ProxyStatus.parse!(input)
    # The lenient walk is this walk with the parameter checks off, so
    # the clean paths count alike.
    expect(allocations { Fast::ProxyStatus.parse!(input) }).to be(:<, 14)
  end

  it "answers valid? in thirteen objects" do
    input = "revproxy1.example.net, ExampleCDN"
    Fast::ProxyStatus.valid?(input)
    # The parse's own count: the boolean mirror adds nothing.
    expect(allocations { Fast::ProxyStatus.valid?(input) }).to be(:<, 14)
  end

  it "constructs a Hop in two objects" do
    identifier = Fast::SFV::Token.new("x")
    Fast::ProxyStatus::Hop.new(identifier)
    # The default params Hash and the frozen Hop.
    expect(allocations { Fast::ProxyStatus::Hop.new(identifier) }).to be(:<, 3)
  end

  it "appends to a held value in four objects" do
    held = Fast::ProxyStatus.parse("a, b")
    hop = Fast::SFV::Token.new("c")
    held.append(hop)
    # The members copy, the params Hash, the Hop, the value object —
    # no re-parse, no re-emit.
    expect(allocations { held.append(hop) }).to be(:<, 5)
  end

  it "appends over a received String in seventeen objects" do
    hop = Fast::SFV::Token.new("c")
    Fast::ProxyStatus.append("a, b", hop)
    # The lenient parse 13, then the held append's four.
    expect(allocations { Fast::ProxyStatus.append("a, b", hop) }).to be(:<, 18)
  end

  it "promotes the section 2 example in thirty objects" do
    header = "SomeOtherProxy, ThisProxy"
    trailer = "ThisProxy; error=read_timeout"
    Fast::ProxyStatus.promote(header, trailer)
    # Two lenient parses, the header copy, the remaining Array, the
    # two value objects, the frozen Promotion.
    expect(allocations { Fast::ProxyStatus.promote(header, trailer) }).to be(:<, 31)
  end

  it "emits in one object" do
    field = Fast::ProxyStatus.parse("revproxy1.example.net, ExampleCDN")
    field.to_s
    # The output String only — the members append into the one buffer.
    expect(allocations { field.to_s }).to be(:<, 2)
  end

  it "parses the Cache-Status section 3 two-layer example in seventeen objects" do
    input = 'OriginCache; hit; ttl=1100, "CDN Company Here"; hit; ttl=545'
    Fast::CacheStatus.parse(input)
    # The Parser, the Token and the quoted String, the four parameter
    # values, the two Items, the two Caches, the mapped Array, the
    # frozen value object.
    expect(allocations { Fast::CacheStatus.parse(input) }).to be(:<, 18)
  end

  it "parses the Cache-Status three-line example in thirty-two objects" do
    input = ["ReverseProxyCache; hit", "ForwardProxyCache; fwd=uri-miss; collapsed; stored",
             "BrowserCache; fwd=uri-miss"]
    Fast::CacheStatus.parse(input)
    # The combined String the Array join builds, then the parse's own
    # count over three members.
    expect(allocations { Fast::CacheStatus.parse(input) }).to be(:<, 33)
  end

  it "falls to the shared empty value on a malformed Cache-Status field in eight objects" do
    Fast::CacheStatus.parse("!!")
    # The SFV parse's failure path and the wrapped ParseError; the
    # empty value is shared and free.
    expect(allocations { Fast::CacheStatus.parse("!!") }).to be(:<, 9)
  end

  it "pays the positioning Scan on a Cache-Status member-violation fall in eleven objects" do
    Fast::CacheStatus.parse("ExampleCache, 5")
    # The parse's own count, the Scan instance, the positioned
    # ParseError and its message — the member failure the lenient parse
    # rescues.
    expect(allocations { Fast::CacheStatus.parse("ExampleCache, 5") }).to be(:<, 12)
  end

  it "parses a Cache-Status field strictly in eleven objects" do
    input = "ExampleCache; hit; ttl=376"
    Fast::CacheStatus.parse!(input)
    # The clean path counts the parse's own — the Scan runs only where
    # an error needs an offset.
    expect(allocations { Fast::CacheStatus.parse!(input) }).to be(:<, 12)
  end

  it "answers Cache-Status valid? in seventeen objects" do
    input = 'OriginCache; hit; ttl=1100, "CDN Company Here"; hit; ttl=545'
    Fast::CacheStatus.valid?(input)
    # The parse's own count: the boolean mirror adds nothing.
    expect(allocations { Fast::CacheStatus.valid?(input) }).to be(:<, 18)
  end

  it "constructs a Cache in two objects" do
    identifier = Fast::SFV::Token.new("x")
    Fast::CacheStatus::Cache.new(identifier)
    # The default params Hash and the frozen Cache.
    expect(allocations { Fast::CacheStatus::Cache.new(identifier) }).to be(:<, 3)
  end

  it "appends to a held Cache-Status value in four objects" do
    held = Fast::CacheStatus.parse("a; hit")
    cache = Fast::SFV::Token.new("c")
    held.append(cache)
    # The members copy, the params Hash, the Cache, the value object —
    # no re-parse, no re-emit.
    expect(allocations { held.append(cache) }).to be(:<, 5)
  end

  it "appends over a received Cache-Status String in fifteen objects" do
    input = "ExampleCache; hit; ttl=376"
    cache = Fast::SFV::Token.new("MyCache")
    Fast::CacheStatus.append(input, cache)
    # The lenient parse 11, then the held append's four.
    expect(allocations { Fast::CacheStatus.append(input, cache) }).to be(:<, 16)
  end

  it "emits a Cache-Status value in one object" do
    field = Fast::CacheStatus.parse('OriginCache; hit; ttl=1100, "CDN Company Here"; hit; ttl=545')
    field.to_s
    # The output String only — the members append into the one buffer.
    expect(allocations { field.to_s }).to be(:<, 2)
  end

  it "parses a two-member targeted field in nine objects" do
    input = "max-age=600, no-store"
    Fast::TargetedCacheControl.parse(input)
    # The Parser, the dictionary Hash with its two key slices and two
    # Items, the violations Array, the keys view, the value object.
    expect(allocations { Fast::TargetedCacheControl.parse(input) }).to be(:<, 10)
  end

  it "falls to the shared empty value on a malformed targeted field in eight objects" do
    Fast::TargetedCacheControl.parse("!!")
    # The SFV parse's failure path and the wrapped ParseError; the
    # empty value is shared and free.
    expect(allocations { Fast::TargetedCacheControl.parse("!!") }).to be(:<, 9)
  end

  it "parses a flagged targeted field in eight objects" do
    Fast::TargetedCacheControl.parse("max-age=60.5")
    # The parse's own count plus the flagged key — the SHOULD-NOT-
    # consume flag is data, never a wire change, and it costs the
    # Array the clean parse builds anyway.
    expect(allocations { Fast::TargetedCacheControl.parse("max-age=60.5") }).to be(:<, 9)
    expect(Fast::TargetedCacheControl.parse("max-age=60.5").violating).to be(:==, ["max-age"])
  end

  it "parses a targeted field strictly in nine objects" do
    input = "max-age=600, no-store"
    Fast::TargetedCacheControl.parse!(input)
    # The lenient walk is this walk with the checks collecting instead
    # of raising, so the clean paths count alike.
    expect(allocations { Fast::TargetedCacheControl.parse!(input) }).to be(:<, 10)
  end

  it "answers targeted valid? in nine objects" do
    input = "max-age=600, no-store"
    Fast::TargetedCacheControl.valid?(input)
    # The parse's own count: the boolean mirror adds nothing.
    expect(allocations { Fast::TargetedCacheControl.valid?(input) }).to be(:<, 10)
  end

  it "constructs a targeted value in five objects" do
    members = { "max-age" => 600 }
    Fast::TargetedCacheControl.new(members)
    # The held Hash, the Item, the violations Array, the keys view, the
    # frozen value object.
    expect(allocations { Fast::TargetedCacheControl.new(members) }).to be(:<, 6)
  end

  it "emits a targeted value in one object" do
    field = Fast::TargetedCacheControl.parse("max-age=600, no-store")
    field.to_s
    # The output String only — the members append into the one buffer.
    expect(allocations { field.to_s }).to be(:<, 2)
  end
end
