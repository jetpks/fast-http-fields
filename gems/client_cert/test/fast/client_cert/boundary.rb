# frozen_string_literal: true

require "fast/client_cert"

# The construction boundary's error contract: a caller-supplied value
# that is classless (a BasicObject descendant) is refused with the
# documented class — SerializeError for field content, ArgumentError
# for the sender-side cut's caller argument — never a raw
# NoMethodError out of a guard that called a method on the value it
# was rejecting. The fuzz harness's emit campaign is the exhaustive
# check over its hostile-value pool.
describe "the construction boundary" do
  it "refuses a classless certificate and chain with SerializeError" do
    expect { Fast::ClientCert::Cert.new(BasicObject.new) }
      .to raise_exception(Fast::ClientCert::SerializeError)
    expect { Fast::ClientCert::Chain.new(BasicObject.new) }
      .to raise_exception(Fast::ClientCert::SerializeError)
    expect { Fast::ClientCert::Chain.new([BasicObject.new]) }
      .to raise_exception(Fast::ClientCert::SerializeError)
  end

  it "refuses a classless per-line count with ArgumentError" do
    expect { Fast::ClientCert::Chain.new([]).split(BasicObject.new) }.to raise_exception(ArgumentError)
  end
end

# The PEM armor rule: a payload region of blank lines alone carries no
# payload, and a no-payload block raises Error — the doc's own
# reading, now the guard's.
describe "Fast::ClientCert.pem_to_field" do
  it "raises Error for a payload region of blank lines alone" do
    blank = "-----BEGIN CERTIFICATE-----\n \n\t\n-----END CERTIFICATE-----\n"
    error = nil
    begin
      Fast::ClientCert.pem_to_field(blank)
    rescue Fast::ClientCert::Error => e
      error = e
    end
    expect(error).to be(:kind_of?, Fast::ClientCert::Error)
  end

  it "keeps a payload block padded with blank lines working" do
    padded = "-----BEGIN CERTIFICATE-----\n\nYWJj\n\n-----END CERTIFICATE-----\n"
    expect(Fast::ClientCert.pem_to_field(padded)).to be(:==, ":YWJj:")
  end
end
