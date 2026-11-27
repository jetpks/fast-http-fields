# frozen_string_literal: true

require "fast/client_cert"
require "digest"
require_relative "vectors"

describe Fast::ClientCert::Chain do
  # The ParseError a strict parse raised, or nil — the frozen offset
  # pins are read off it.
  def strict_error_of(input)
    Fast::ClientCert::Chain.parse!(input)
    nil
  rescue Fast::ClientCert::ParseError => e
    e
  end

  # The SerializeError a construction raised, or nil.
  def construction_error_of(ders)
    Fast::ClientCert::Chain.new(ders)
    nil
  rescue Fast::ClientCert::SerializeError => e
    e
  end

  describe ".parse" do
    it "reads the Appendix A Figure 3 value" do
      chain = Fast::ClientCert::Chain.parse(ClientCertVectors::FIG3)
      expect(chain).to be(:kind_of?, Fast::ClientCert::Chain)
      expect(chain.size).to be(:==, 2)
      expect(chain.ders.map(&:bytesize)).to be(:==, ClientCertVectors::DER_BYTESIZES[1..])
      expect(chain.ders.map { |der| Digest::SHA256.hexdigest(der) }).to be(:==, ClientCertVectors::DER_SHA256[1..])
      expect(chain.ders).to be(:==, Fast::SFV.parse_list(ClientCertVectors::FIG3).map(&:value))
      expect(chain.to_s).to be(:==, ClientCertVectors::FIG3)
    end

    it "combines the split-line form (9651 4.2, 9440 2.3)" do
      chain = Fast::ClientCert::Chain.parse(ClientCertVectors::FIG3)
      split = Fast::ClientCert::Chain.parse([ClientCertVectors::FIG3_MEMBER1, " #{ClientCertVectors::FIG3_MEMBER2}"])
      expect(split.ders).to be(:==, chain.ders)
      expect(split.to_s).to be(:==, ClientCertVectors::FIG3)
    end

    it "preserves member parameters through the re-emit" do
      chain = Fast::ClientCert::Chain.parse(":aGVsbG8=:;q=1, :d29ybGQ=:")
      expect(chain.ders).to be(:==, %w[hello world])
      expect(chain.to_s).to be(:==, ":aGVsbG8=:;q=1, :d29ybGQ=:")
    end

    it "parses the empty field to the shared empty value" do
      empty = Fast::ClientCert::Chain.parse("")
      expect(empty.empty?).to be(:==, true)
      expect(empty.to_s).to be(:==, "")
      expect(Fast::ClientCert::Chain.parse("!!")).to be(:equal?, empty)
    end

    it "ignores the whole field on malformed input (9651 2.2)" do
      ["!!", ":", "a,", "not a field", ":aGVsbG8=: :d29ybGQ=:"].each do |input|
        fallen = Fast::ClientCert::Chain.parse(input)
        expect(fallen.empty?).to be(:==, true)
        expect(fallen.to_s).to be(:==, "")
      end
    end

    it "ignores the whole field on the empty Byte Sequence (2.1: DER is never zero bytes)" do
      expect(Fast::ClientCert::Chain.parse("::").ders).to be(:==, [])
      expect(Fast::ClientCert::Chain.parse("::").empty?).to be(:==, true)
      expect(Fast::ClientCert::Chain.valid?("::")).to be(:==, false)
      error = strict_error_of("::")
      expect(error.offset).to be(:==, 0)
      expect(error.message).to be(:==, %(a Client-Cert-Chain member is a Byte Sequence (got "")))
    end

    it "ignores the whole field on any non-Byte-Sequence member (2.3)" do
      [":aGVsbG8=:, 5", "5, :aGVsbG8=:", ":aGVsbG8=:, \"str\"", ":aGVsbG8=:, token", "(:aGVsbG8=:)",
       ":aGVsbG8=:, (:d29ybGQ=:)"].each do |input|
        expect(Fast::ClientCert::Chain.parse(input).empty?).to be(:==, true)
      end
    end

    it "does no member-level filtering — a good member beside a bad one drops" do
      mixed = Fast::ClientCert::Chain.parse(":aGVsbG8=:, 5, :d29ybGQ=:")
      expect(mixed.empty?).to be(:==, true)
      expect(mixed.to_s).to be(:==, "")
    end

    it "raises TypeError for a wrong input type" do
      [nil, 5, :sym, {}].each do |input|
        type_error = false
        begin
          Fast::ClientCert::Chain.parse(input)
        rescue TypeError
          type_error = true
        end
        expect(type_error).to be(:==, true)
      end
    end

    it "answers frozen value objects" do
      chain = Fast::ClientCert::Chain.parse(ClientCertVectors::FIG3)
      expect(chain.frozen?).to be(:==, true)
      expect(chain.ders.frozen?).to be(:==, true)
      expect(chain.ders[0].frozen?).to be(:==, true)
    end
  end

  describe ".parse!" do
    it "wraps the substrate failure with its offset" do
      expect(strict_error_of("!!").offset).to be(:==, 0)
      expect(strict_error_of("a,").offset).to be(:==, 2)
    end

    it "raises the member constraint at the first offender" do
      { ":aGVsbG8=:, 5" => 12, "5, :aGVsbG8=:" => 0, ":aGVsbG8=:, \"str\"" => 12,
        "(:aGVsbG8=:)" => 0, ":aGVsbG8=:;k=\"a,b\", 5" => 20, ":aGVsbG8=:, 5, 6" => 12 }.each do |input, offset|
        expect(strict_error_of(input).offset).to be(:==, offset)
      end
    end

    it "raises after a display-string parameter ending in a backslash" do
      # RFC 9651 §4.2.10: a display string's backslash is literal
      # content and only DQUOTE closes, so a=%"\" is a legal parameter
      # value the positioning must cross intact — the later member is
      # raised at its own identifier, never past the field's end.
      expect(strict_error_of(%(:AAAA:;a=%"\\", 5)).offset).to be(:==, 15)
      expect(strict_error_of(%(:AAAA:;a=%"a", 5)).offset).to be(:==, 15)
    end

    it "combines the Array input before positioning (9651 4.2)" do
      expect(strict_error_of([":aGVsbG8=:", " 5"]).offset).to be(:==, 13)
    end

    it "raises the first offender in List order" do
      expect(strict_error_of("5, :aGVsbG8=:, 5").offset).to be(:==, 0)
    end

    it "names the field and the type 2.3 states" do
      message = strict_error_of(":aGVsbG8=:, 5").message
      expect(message.include?("Byte Sequence")).to be(:==, true)
      expect(message.include?("Integer")).to be(:==, true)
      expect(strict_error_of("(:aGVsbG8=:)").message.include?("InnerList")).to be(:==, true)
    end

    it "answers the value for the strict path" do
      chain = Fast::ClientCert::Chain.parse!(ClientCertVectors::FIG3)
      expect(chain.to_s).to be(:==, ClientCertVectors::FIG3)
    end
  end

  describe ".valid?" do
    it "mirrors the strict parse" do
      lines = [ClientCertVectors::FIG3_MEMBER1, ClientCertVectors::FIG3_MEMBER2]
      expect(Fast::ClientCert::Chain.valid?(ClientCertVectors::FIG3)).to be(:==, true)
      expect(Fast::ClientCert::Chain.valid?(lines)).to be(:==, true)
      expect(Fast::ClientCert::Chain.valid?(":aGVsbG8=:;q=1")).to be(:==, true)
      expect(Fast::ClientCert::Chain.valid?("")).to be(:==, true)
    end

    it "answers false for malformed and member-violating content" do
      [":aGVsbG8=:, 5", "5", "!!", "(:aGVsbG8=:)", "a,"].each do |input|
        expect(Fast::ClientCert::Chain.valid?(input)).to be(:==, false)
      end
    end

    it "answers false for a wrong input type" do
      expect(Fast::ClientCert::Chain.valid?(nil)).to be(:==, false)
      expect(Fast::ClientCert::Chain.valid?(5)).to be(:==, false)
    end
  end

  describe "#new" do
    it "emits the canonical List form" do
      chain = Fast::ClientCert::Chain.new(["hello".b, "world".b])
      expect(chain.to_s).to be(:==, ":aGVsbG8=:, :d29ybGQ=:")
      expect(chain.ders).to be(:==, %w[hello world])
      expect(chain.size).to be(:==, 2)
    end

    it "builds the empty value from the empty Array" do
      empty = Fast::ClientCert::Chain.new([])
      expect(empty.empty?).to be(:==, true)
      expect(empty.to_s).to be(:==, "")
    end

    it "refuses a members shape that would not emit as Byte Sequences" do
      [["hello", "world".b], ["hello".b, Fast::SFV::Token.new("tok")], [5], "hello".b].each do |ders|
        error = construction_error_of(ders)
        expect(error).to be(:kind_of?, Fast::ClientCert::SerializeError)
        expect(error.offset).to be(:==, 0)
      end
    end

    it "freezes each DER in place" do
      der = +"hello".b
      built = Fast::ClientCert::Chain.new([der])
      expect(der.frozen?).to be(:==, true)
      expect(built.frozen?).to be(:==, true)
      expect(built.ders.frozen?).to be(:==, true)
    end
  end

  describe "the reader set" do
    it "indexes and iterates the DERs" do
      chain = Fast::ClientCert::Chain.parse(ClientCertVectors::FIG3)
      expect(chain[0].bytesize).to be(:==, 490)
      expect(chain[1].bytesize).to be(:==, 522)
      expect(chain[2]).to be(:==, nil)
      ders = []
      chain.each { |der| ders << der }
      expect(ders.size).to be(:==, 2)
      expect(chain.each.to_a.size).to be(:==, 2)
    end
  end

  describe "#split" do
    it "cuts one certificate per line at 1" do
      whole = Fast::ClientCert::Chain.parse(ClientCertVectors::FIG3)
      lines = whole.split(1)
      expect(lines.size).to be(:==, 2)
      expect(lines[0]).to be(:==, ClientCertVectors::FIG3_MEMBER1)
      expect(lines[1]).to be(:==, ClientCertVectors::FIG3_MEMBER2)
      expect(lines.frozen?).to be(:==, true)
    end

    it "keeps the whole chain in one value at 2" do
      whole = Fast::ClientCert::Chain.parse(ClientCertVectors::FIG3)
      expect(whole.split(2).size).to be(:==, 1)
      expect(whole.split(2)[0]).to be(:==, ClientCertVectors::FIG3)
    end

    it "recombines through the Array entry point" do
      whole = Fast::ClientCert::Chain.parse(ClientCertVectors::FIG3)
      recombined = Fast::ClientCert::Chain.parse(whole.split(1))
      expect(recombined.to_s).to be(:==, ClientCertVectors::FIG3)
      expect(recombined).to be(:==, whole)
    end

    it "answers no lines for the empty chain" do
      expect(Fast::ClientCert::Chain.new([]).split(1)).to be(:==, [])
    end

    it "raises ArgumentError for a non-positive per_line" do
      whole = Fast::ClientCert::Chain.parse(ClientCertVectors::FIG3)
      [0, -1, "1", nil].each do |per_line|
        argument_error = false
        begin
          whole.split(per_line)
        rescue ArgumentError
          argument_error = true
        end
        expect(argument_error).to be(:==, true)
      end
    end
  end

  describe "equality and inspect" do
    it "compares by canonical wire form within the class" do
      one = Fast::ClientCert::Chain.parse(ClientCertVectors::FIG3)
      other = Fast::ClientCert::Chain.parse(ClientCertVectors::FIG3)
      expect(one == other).to be(:==, true)
      expect(one.hash == other.hash).to be(:==, true)
      expect(one == Fast::ClientCert::Chain.new(one.ders)).to be(:==, true)
      expect(one == one.ders).to be(:==, false)
      expect(one == Fast::ClientCert::Cert.parse(ClientCertVectors::FIG2)).to be(:==, false)
    end

    it "inspects as the wire form" do
      chain = Fast::ClientCert::Chain.parse(ClientCertVectors::FIG3)
      expect(chain.inspect).to be(:==, "#<Fast::ClientCert::Chain #{ClientCertVectors::FIG3}>")
      expect(Fast::ClientCert::Chain.new([]).inspect).to be(:==, "#<Fast::ClientCert::Chain>")
    end
  end
end
