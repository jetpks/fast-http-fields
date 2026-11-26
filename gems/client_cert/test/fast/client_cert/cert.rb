# frozen_string_literal: true

require "fast/client_cert"
require "digest"
require_relative "vectors"

describe Fast::ClientCert::Cert do
  # The ParseError a strict parse raised, or nil — the frozen offset
  # pins are read off it.
  def strict_error_of(input)
    Fast::ClientCert::Cert.parse!(input)
    nil
  rescue Fast::ClientCert::ParseError => e
    e
  end

  # The SerializeError a construction raised, or nil.
  def construction_error_of(der)
    Fast::ClientCert::Cert.new(der)
    nil
  rescue Fast::ClientCert::SerializeError => e
    e
  end

  describe ".parse" do
    it "reads the Appendix A Figure 2 value" do
      cert = Fast::ClientCert::Cert.parse(ClientCertVectors::FIG2)
      expect(cert).to be(:kind_of?, Fast::ClientCert::Cert)
      expect(cert.der.bytesize).to be(:==, ClientCertVectors::DER_BYTESIZES[0])
      expect(Digest::SHA256.hexdigest(cert.der)).to be(:==, ClientCertVectors::DER_SHA256[0])
      expect(cert.der).to be(:==, Fast::SFV.parse_item(ClientCertVectors::FIG2).value)
      expect(cert.der.encoding.name).to be(:==, "ASCII-8BIT")
      expect(cert.der.frozen?).to be(:==, true)
      expect(cert.to_s).to be(:==, ClientCertVectors::FIG2)
    end

    it "preserves parameters through the canonical re-emit" do
      cert = Fast::ClientCert::Cert.parse(":aGVsbG8=:;q=1")
      expect(cert.der).to be(:==, "hello")
      expect(cert.to_s).to be(:==, ":aGVsbG8=:;q=1")
    end

    it "answers nil for a malformed field (RFC 9651 2.2, RFC 9440 4)" do
      ["!!", "", ":", "not a field", ":aGVsbG8=: :d29ybGQ=:,"].each do |input|
        expect(Fast::ClientCert::Cert.parse(input)).to be(:==, nil)
      end
    end

    it "answers nil for a list-shaped value (the singleton rule, 2.2)" do
      expect(Fast::ClientCert::Cert.parse(":aGVsbG8=:, :d29ybGQ=:")).to be(:==, nil)
      expect(Fast::ClientCert::Cert.parse("(:aGVsbG8=:)")).to be(:==, nil)
      expect(Fast::ClientCert::Cert.parse([":aGVsbG8=:", ":d29ybGQ=:"])).to be(:==, nil)
    end

    it "answers nil for an item that is not a Byte Sequence (2.1)" do
      ["5", "\"str\"", "token", "?0", "@1", "%22foo%22"].each do |input|
        expect(Fast::ClientCert::Cert.parse(input)).to be(:==, nil)
      end
    end

    it "discards the OWS around the value (9651 4.2)" do
      cert = Fast::ClientCert::Cert.parse(" :aGVsbG8=:  ")
      expect(cert.der).to be(:==, "hello")
    end

    it "raises TypeError for a wrong input type" do
      [nil, 5, :sym, {}].each do |input|
        type_error = false
        begin
          Fast::ClientCert::Cert.parse(input)
        rescue TypeError
          type_error = true
        end
        expect(type_error).to be(:==, true)
      end
    end
  end

  describe ".parse!" do
    it "wraps the substrate failure with its offset" do
      { "!!" => 0, "(:aGVsbG8=:)" => 0, ":aGVsbG8=:, :d29ybGQ=:" => 10 }.each do |input, offset|
        expect(strict_error_of(input).offset).to be(:==, offset)
      end
      expect(strict_error_of([" 5", ":aGVsbG8=:"]).offset).to be(:==, 2)
    end

    it "raises the Byte Sequence constraint at the value start" do
      expect(strict_error_of("5").offset).to be(:==, 0)
      expect(strict_error_of(" 5").offset).to be(:==, 1)
      expect(strict_error_of("\"str\"").offset).to be(:==, 0)
    end

    it "names the type 2.1 states" do
      message = strict_error_of("5").message
      expect(message.include?("Byte Sequence")).to be(:==, true)
      expect(message.include?("Integer")).to be(:==, true)
    end

    it "answers the value for the strict path" do
      cert = Fast::ClientCert::Cert.parse!(ClientCertVectors::FIG2)
      expect(cert.to_s).to be(:==, ClientCertVectors::FIG2)
    end
  end

  describe ".valid?" do
    it "mirrors the parse" do
      expect(Fast::ClientCert::Cert.valid?(ClientCertVectors::FIG2)).to be(:==, true)
      expect(Fast::ClientCert::Cert.valid?(":aGVsbG8=:;q=1")).to be(:==, true)
      expect(Fast::ClientCert::Cert.valid?(" :aGVsbG8=:")).to be(:==, true)
    end

    it "answers false for malformed and non-Byte-Sequence content" do
      ["!!", "", "5", "\"str\"", "(:aGVsbG8=:)", ":aGVsbG8=:, :d29ybGQ=:"].each do |input|
        expect(Fast::ClientCert::Cert.valid?(input)).to be(:==, false)
      end
    end

    it "answers false for a wrong input type" do
      expect(Fast::ClientCert::Cert.valid?(nil)).to be(:==, false)
      expect(Fast::ClientCert::Cert.valid?(5)).to be(:==, false)
    end
  end

  describe "#new" do
    it "emits the canonical form" do
      cert = Fast::ClientCert::Cert.new("hello".b)
      expect(cert.to_s).to be(:==, ":aGVsbG8=:")
      expect(cert.der).to be(:==, "hello")
      expect(cert.der.encoding.name).to be(:==, "ASCII-8BIT")
    end

    it "refuses a value that would not emit as a Byte Sequence" do
      ["hello", Fast::SFV::Token.new("tok"), 5, nil, :sym].each do |der|
        error = construction_error_of(der)
        expect(error).to be(:kind_of?, Fast::ClientCert::SerializeError)
        expect(error.offset).to be(:==, 0)
        expect(error.message.include?("Byte Sequence")).to be(:==, true)
      end
    end

    it "freezes the DER in place" do
      der = +"hello".b
      cert = Fast::ClientCert::Cert.new(der)
      expect(der.frozen?).to be(:==, true)
      expect(cert.frozen?).to be(:==, true)
      expect(cert.der.frozen?).to be(:==, true)
    end
  end

  describe "equality and inspect" do
    it "compares by canonical wire form within the class" do
      one = Fast::ClientCert::Cert.parse(":aGVsbG8=:")
      other = Fast::ClientCert::Cert.parse(":aGVsbG8=:")
      expect(one == other).to be(:==, true)
      expect(one.eql?(other)).to be(:==, true)
      expect(one.hash == other.hash).to be(:==, true)
      expect(one == Fast::ClientCert::Cert.new("hello".b)).to be(:==, true)
      expect(one == Fast::SFV.parse_item(":aGVsbG8=:")).to be(:==, false)
      expect(one.inspect).to be(:==, "#<Fast::ClientCert::Cert :aGVsbG8=:>")
    end
  end
end
