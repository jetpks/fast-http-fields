# frozen_string_literal: true

require "fast/priority"

# Allocation budgets for the eight paths: what one operation costs in
# Ruby objects beyond the input. Counts are GC.stat, averaged over runs
# so a one-off allocation outside the block (GC.stat's own, under
# coverage) does not count, and everything a measured block touches is
# a local. Measured on Ruby 4.0.10, then frozen: a parse of "u=5, i" 8
# (the engine object, the Fast::SFV Parser, the dictionary Hash with
# its two key Strings and two Items, and the Parameters); a malformed
# field's fall to the defaults 8 (the engine, the SFV parse's own
# failure path — the raised error with its message — and the
# all-defaults Parameters with its fresh empty members Hash); the emit
# 1 (the output String, whatever the member count); the merge 2 (the
# merged members Hash and the new Parameters); each frame encode 2
# (the 4-byte word or varint pack and the to_s); each frame decode 10
# (the bytesliced field value, the engine, ONE SFV Dictionary parse —
# the engine answers both the §4 view and the §7 error off the same
# parse, never two — the Parameters, and the frozen Frame result).
#
# The parse count matches the family's fast-sfv budgets in shape: the
# gem adds only its own value object on top of the substrate's parse.
describe "allocations" do
  # Objects allocated per run of the block, averaged over +times+ runs.
  def allocations(times = 100, &block)
    before = GC.stat(:total_allocated_objects)
    times.times(&block)
    (GC.stat(:total_allocated_objects) - before) / times.to_f
  end

  it "parses a field in eight objects" do
    input = "u=5, i"
    Fast::Priority.parse(input)
    # The engine, the SFV Parser, the dictionary Hash with its two keys
    # and two Items, and the Parameters.
    expect(allocations { Fast::Priority.parse(input) }).to be(:<, 9)
  end

  it "falls to the defaults on a malformed field in eight objects" do
    input = "!!"
    Fast::Priority.parse(input)
    # The engine, the SFV parse's failure path (the error and its
    # message), and the all-defaults Parameters with its members Hash.
    expect(allocations { Fast::Priority.parse(input) }).to be(:<, 9)
  end

  it "emits in one object" do
    priority = Fast::Priority.parse("u=5, i")
    priority.to_s
    # The output String only — the members append into the one buffer.
    expect(allocations { priority.to_s }).to be(:<, 2)
  end

  it "merges in two objects" do
    left = Fast::Priority.parse("u=5, i")
    right = Fast::Priority.parse("u=1")
    left.merge(right)
    # The merged members Hash and the new Parameters.
    expect(allocations { left.merge(right) }).to be(:<, 3)
  end

  it "encodes an h2 payload in two objects" do
    priority = Fast::Priority.parse("u=1, i")
    Fast::Priority::H2.encode_payload(5, priority)
    # The 4-byte word pack and the to_s.
    expect(allocations { Fast::Priority::H2.encode_payload(5, priority) }).to be(:<, 3)
  end

  it "decodes an h2 payload in ten objects" do
    payload = (["00000005"].pack("H*") << "u=5, i")
    Fast::Priority::H2.decode_payload(payload)
    # The bytesliced field value, the engine, the ONE SFV Dictionary
    # parse (Parser, Hash, two keys, two Items), the Parameters and the
    # frozen Frame.
    expect(allocations { Fast::Priority::H2.decode_payload(payload) }).to be(:<, 11)
  end

  it "encodes an h3 payload in two objects" do
    priority = Fast::Priority.parse("u=1, i")
    Fast::Priority::H3.encode_payload(4, priority)
    # The minimal varint pack and the to_s.
    expect(allocations { Fast::Priority::H3.encode_payload(4, priority) }).to be(:<, 3)
  end

  it "decodes an h3 payload in ten objects" do
    payload = (["04"].pack("H*") << "u=5, i")
    Fast::Priority::H3.decode_payload(payload)
    # The bytesliced field value, the engine, the ONE SFV Dictionary
    # parse (Parser, Hash, two keys, two Items), the Parameters and the
    # frozen Frame.
    expect(allocations { Fast::Priority::H3.decode_payload(payload) }).to be(:<, 11)
  end
end
