# frozen_string_literal: true

require "fast/digest"

# Allocation budgets for the eight paths: what one operation costs in
# Ruby objects beyond the input. Counts are GC.stat, averaged over runs
# so a one-off allocation outside the block (GC.stat's own, under
# coverage) does not count, and everything a measured block touches is
# a local. Measured on Ruby 4.0.10, then frozen: a parse of the B.1
# value 10 (the Fast::SFV Parser, the dictionary Hash with its key
# String and Item, the Scan with its offsets Hash and key slice, and
# the frozen value object with its keys view); a malformed field's fall
# to the empty value 9 (the SFV parse's own failure path — the raised
# error with its message — the wrapped ParseError, and the empty value
# object with its keys view); the three-member preference parse 15 (the
# Parser, the dictionary with three keys and three Items, the Scan with
# its offsets Hash and three key slices, the value object and its keys
# view); the emit 1 (the output String, whatever the member count); the
# compute 2 (the stdlib's digest bytes and its internal object); the
# .of compute-and-construct 8 (the compute 2, then construction's six:
# the two Hashes a literal member argument costs, the Item, the value
# object and its keys view); the strict parse 10 (the parse path's own
# count — the lenient parse is the strict path rescued, so the two
# count alike); the valid? mirror 15 (the preference parse's own count:
# the mirror adds nothing).
#
# The parse count matches the family's budgets in shape: the gem adds
# its Scan, its offsets and its value object on top of the substrate's
# parse, and one object per member for the key each walk records.
describe "allocations" do
  # Objects allocated per run of the block, averaged over +times+ runs.
  def allocations(times = 100, &block)
    before = GC.stat(:total_allocated_objects)
    times.times(&block)
    (GC.stat(:total_allocated_objects) - before) / times.to_f
  end

  it "parses an Integrity field in ten objects" do
    input = "sha-256=:RK/0qy18MlBSVnWgjwz6lZEWjP/lF5HF9bvEF8FabDg=:"
    Fast::Digest::ReprDigest.parse(input)
    # The SFV Parser, the dictionary Hash with its key and Item, the
    # Scan with its offsets Hash and key slice, the value object and
    # its keys view.
    expect(allocations { Fast::Digest::ReprDigest.parse(input) }).to be(:<, 11)
  end

  it "falls to the empty value on a malformed field in nine objects" do
    Fast::Digest::ReprDigest.parse("!!")
    # The SFV parse's failure path (the error and its message), the
    # wrapped ParseError, and the empty value object with its keys view.
    expect(allocations { Fast::Digest::ReprDigest.parse("!!") }).to be(:<, 10)
  end

  it "parses a three-member preference field in fifteen objects" do
    input = "sha-512=3, sha-256=10, unixsum=0"
    Fast::Digest::WantReprDigest.parse(input)
    # The Parser, the dictionary with three keys and three Items, the
    # Scan's offsets Hash with three key slices, the value object and
    # its keys view.
    expect(allocations { Fast::Digest::WantReprDigest.parse(input) }).to be(:<, 16)
  end

  it "emits in one object" do
    field = Fast::Digest::ReprDigest.parse("sha-256=:RK/0qy18MlBSVnWgjwz6lZEWjP/lF5HF9bvEF8FabDg=:")
    field.to_s
    # The output String only — the members append into the one buffer.
    expect(allocations { field.to_s }).to be(:<, 2)
  end

  it "computes in two objects" do
    body = "the bytes to hash"
    Fast::Digest.compute("sha-256", body)
    # The stdlib's digest String and its one internal object.
    expect(allocations { Fast::Digest.compute("sha-256", body) }).to be(:<, 3)
  end

  it "computes and constructs with .of in eight objects" do
    body = "the bytes to hash"
    Fast::Digest::ReprDigest.of("sha-256", body)
    # The compute 2, then construction's six: the two Hashes a literal
    # member argument costs, the Item, the value object and its keys
    # view.
    expect(allocations { Fast::Digest::ReprDigest.of("sha-256", body) }).to be(:<, 9)
  end

  it "parses strictly in ten objects" do
    input = "sha-256=:RK/0qy18MlBSVnWgjwz6lZEWjP/lF5HF9bvEF8FabDg=:"
    Fast::Digest::ReprDigest.parse!(input)
    # The lenient parse is this path rescued, so the count is the same.
    expect(allocations { Fast::Digest::ReprDigest.parse!(input) }).to be(:<, 11)
  end

  it "answers valid? in fifteen objects" do
    input = "sha-512=3, sha-256=10, unixsum=0"
    Fast::Digest::WantReprDigest.valid?(input)
    # The preference parse's own count: the mirror adds nothing.
    expect(allocations { Fast::Digest::WantReprDigest.valid?(input) }).to be(:<, 16)
  end
end
