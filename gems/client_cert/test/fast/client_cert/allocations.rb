# frozen_string_literal: true

require "fast/client_cert"
require_relative "vectors"

# Allocation budgets for the nineteen paths: what one operation costs
# in Ruby objects beyond the input. Counts are GC.stat, averaged over
# runs so a one-off allocation outside the block (GC.stat's own, under
# coverage) does not count, and everything a measured block touches is
# a local. Measured on Ruby 4.0.10, then frozen as ceilings: the
# Cert parse of the Appendix A value 4 (the Fast::SFV Parser, the Item
# and its decoded base64 String, and the Cert value object); the
# malformed fall to nil 5 (the SFV parse's own failure path — the
# raised error with its message — rescued raw, nothing built); the
# strict parse 4 and the valid? mirror 4 (the parse path's own count:
# the mirror adds nothing); construction 2 (the Item and the value
# object — the params Hash is the shared frozen constant); the emit 1
# (the output String). The Chain parse of the Appendix A value 8 (the
# Parser, the list Array with two Items and two decoded Strings, the
# value object and its ders view); the split-lines parse 9 (the
# substrate's own line joining on top); the malformed fall to the
# shared empty value 6 (the SFV failure path, rescued raw — the EMPTY
# singleton is built once at load); the member-violation fall 6 (the
# List parse itself; no error is constructed on the lenient path); the
# strict parse 8 and the valid? mirror 8; construction 5 (the items
# Array, the two Items, the value object and its ders view); the emit
# 1; the split 5 (the lines Array, one slice Array and one
# serialization String per line). The PEM surgery: pem_to_field 28
# (the split Array with one String per line, the payload slice, the
# stripped payload lines, the joined base64 and the field value);
# field_to_pem 12 (the validated interior slice, the block String and
# one 64-character slice per payload line, the armor appended in
# place); pems_to_field 66 (the per-block surgery twice and the
# joined members); field_to_pems 35 (the member split, the stripped
# members and the per-member blocks).
#
# The counts are the machine's and the implementation's: the same
# paths on another interpreter, or after another idiom pass, may count
# differently — the frozen ceilings are the budget, not a promise of
# the exact number.
describe "allocations" do
  # Objects allocated per run of the block, averaged over +times+ runs.
  def allocations(times = 100, &block)
    before = GC.stat(:total_allocated_objects)
    times.times(&block)
    (GC.stat(:total_allocated_objects) - before) / times.to_f
  end

  it "parses the Client-Cert field in four objects" do
    Fast::ClientCert::Cert.parse(ClientCertVectors::FIG2)
    # The SFV Parser, the Item with its decoded String, the value
    # object.
    expect(allocations { Fast::ClientCert::Cert.parse(ClientCertVectors::FIG2) }).to be(:<, 5)
  end

  it "falls to nil on a malformed field in five objects" do
    Fast::ClientCert::Cert.parse("!!")
    # The SFV parse's failure path — the error and its message —
    # rescued raw: nothing is built on the fall.
    expect(allocations { Fast::ClientCert::Cert.parse("!!") }).to be(:<, 7)
  end

  it "parses the Client-Cert field strictly in four objects" do
    Fast::ClientCert::Cert.parse!(ClientCertVectors::FIG2)
    # The lenient path's own count: the wrap is spent only on failure.
    expect(allocations { Fast::ClientCert::Cert.parse!(ClientCertVectors::FIG2) }).to be(:<, 5)
  end

  it "answers valid? for the Client-Cert field in four objects" do
    Fast::ClientCert::Cert.valid?(ClientCertVectors::FIG2)
    # The parse path's own count: the mirror adds nothing.
    expect(allocations { Fast::ClientCert::Cert.valid?(ClientCertVectors::FIG2) }).to be(:<, 5)
  end

  it "constructs a Cert in two objects" do
    der = "hello".b
    Fast::ClientCert::Cert.new(der)
    # The Item and the value object — the params Hash is the shared
    # frozen constant.
    expect(allocations { Fast::ClientCert::Cert.new(der) }).to be(:<, 4)
  end

  it "emits the Client-Cert field in one object" do
    cert = Fast::ClientCert::Cert.parse(ClientCertVectors::FIG2)
    cert.to_s
    # The output String only.
    expect(allocations { cert.to_s }).to be(:<, 2)
  end

  it "parses the Client-Cert-Chain field in eight objects" do
    Fast::ClientCert::Chain.parse(ClientCertVectors::FIG3)
    # The SFV Parser, the list Array with two Items and two decoded
    # Strings, the value object and its ders view.
    expect(allocations { Fast::ClientCert::Chain.parse(ClientCertVectors::FIG3) }).to be(:<, 9)
  end

  it "parses the split-line form in nine objects" do
    lines = [ClientCertVectors::FIG3_MEMBER1, " #{ClientCertVectors::FIG3_MEMBER2}"]
    Fast::ClientCert::Chain.parse(lines)
    # The substrate's own line joining, then the parse path's count.
    expect(allocations { Fast::ClientCert::Chain.parse(lines) }).to be(:<, 13)
  end

  it "falls to the empty value on a malformed field in six objects" do
    Fast::ClientCert::Chain.parse("!!")
    # The SFV failure path, rescued raw — the EMPTY singleton is
    # built once at load.
    expect(allocations { Fast::ClientCert::Chain.parse("!!") }).to be(:<, 8)
  end

  it "falls to the empty value on a member violation in six objects" do
    Fast::ClientCert::Chain.parse(":aGVsbG8=:, 5")
    # The List parse itself; no error is constructed on the lenient
    # path.
    expect(allocations { Fast::ClientCert::Chain.parse(":aGVsbG8=:, 5") }).to be(:<, 10)
  end

  it "parses the Client-Cert-Chain field strictly in eight objects" do
    Fast::ClientCert::Chain.parse!(ClientCertVectors::FIG3)
    # The lenient path's own count: the Scan and the wrap are spent
    # only on failure.
    expect(allocations { Fast::ClientCert::Chain.parse!(ClientCertVectors::FIG3) }).to be(:<, 9)
  end

  it "answers valid? for the Client-Cert-Chain field in eight objects" do
    Fast::ClientCert::Chain.valid?(ClientCertVectors::FIG3)
    # The parse path's own count: the mirror adds nothing.
    expect(allocations { Fast::ClientCert::Chain.valid?(ClientCertVectors::FIG3) }).to be(:<, 9)
  end

  it "constructs a Chain in five objects" do
    ders = ["hello".b, "world".b]
    Fast::ClientCert::Chain.new(ders)
    # The items Array, the two Items, the value object and its ders
    # view.
    expect(allocations { Fast::ClientCert::Chain.new(ders) }).to be(:<, 9)
  end

  it "emits the Client-Cert-Chain field in one object" do
    chain = Fast::ClientCert::Chain.parse(ClientCertVectors::FIG3)
    chain.to_s
    # The output String only — the members append into the one
    # buffer.
    expect(allocations { chain.to_s }).to be(:<, 2)
  end

  it "splits one certificate per line in five objects" do
    whole = Fast::ClientCert::Chain.parse(ClientCertVectors::FIG3)
    whole.split(1)
    # The lines Array, one slice Array and one serialization String
    # per line.
    expect(allocations { whole.split(1) }).to be(:<, 6)
  end

  it "converts a PEM block to a field value in twenty-eight objects" do
    Fast::ClientCert.pem_to_field(ClientCertVectors::BLOCK1)
    # The split Array with one String per line, the payload slice,
    # the stripped payload lines, the joined base64 and the field
    # value.
    expect(allocations { Fast::ClientCert.pem_to_field(ClientCertVectors::BLOCK1) }).to be(:<, 29)
  end

  it "converts a field value to a PEM block in twelve objects" do
    Fast::ClientCert.field_to_pem(ClientCertVectors::FIG2)
    # The validated interior slice, the block String and one
    # 64-character slice per payload line — the armor appends into
    # the buffer in place.
    expect(allocations { Fast::ClientCert.field_to_pem(ClientCertVectors::FIG2) }).to be(:<, 14)
  end

  it "joins PEM blocks into a chain value in sixty-six objects" do
    blocks = [ClientCertVectors::BLOCK2, ClientCertVectors::BLOCK3]
    Fast::ClientCert.pems_to_field(blocks)
    # The per-block surgery twice, then the joined members.
    expect(allocations { Fast::ClientCert.pems_to_field(blocks) }).to be(:<, 68)
  end

  it "splits a chain value into its blocks in thirty-five objects" do
    Fast::ClientCert.field_to_pems(ClientCertVectors::FIG3)
    # The member split with one String per member, the stripped
    # members, and the per-member blocks.
    expect(allocations { Fast::ClientCert.field_to_pems(ClientCertVectors::FIG3) }).to be(:<, 38)
  end
end
