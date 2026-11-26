# frozen_string_literal: true

require "fast/proxy_status"

# Allocation budgets for the ten paths: what one operation costs in
# Ruby objects beyond the input. Counts are GC.stat, averaged over runs
# so a one-off allocation outside the block (GC.stat's own, under
# coverage) does not count, and everything a measured block touches is
# a local. Measured on Ruby 4.0.10, then frozen: the two-member parse
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
end
