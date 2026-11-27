# frozen_string_literal: true

require "fast/client_cert"
require_relative "vectors"

describe Fast::ClientCert do
  describe ".pem_to_field" do
    it "converts the Appendix A blocks to the field values (9440 2.1)" do
      expect(Fast::ClientCert.pem_to_field(ClientCertVectors::BLOCK1)).to be(:==, ClientCertVectors::FIG2)
      expect(Fast::ClientCert.pem_to_field(ClientCertVectors::BLOCK2)).to be(:==, ClientCertVectors::FIG3_MEMBER1)
      expect(Fast::ClientCert.pem_to_field(ClientCertVectors::BLOCK3)).to be(:==, ClientCertVectors::FIG3_MEMBER2)
    end

    it "tolerates blank lines around the block" do
      padded = "\n\n#{ClientCertVectors::BLOCK1}\n"
      expect(Fast::ClientCert.pem_to_field(padded)).to be(:==, ClientCertVectors::FIG2)
    end

    it "tolerates CRLF line endings" do
      crlf = ClientCertVectors::BLOCK1.gsub("\n", "\r\n")
      expect(Fast::ClientCert.pem_to_field(crlf)).to be(:==, ClientCertVectors::FIG2)
    end

    it "raises Error for armor-shape failures" do
      ["", "hello", "-----BEGIN CERTIFICATE-----\n",
       "-----BEGIN CERTIFICATE-----\n-----END CERTIFICATE-----\n"].each do |bad|
        usage_error = false
        begin
          Fast::ClientCert.pem_to_field(bad)
        rescue Fast::ClientCert::Error
          usage_error = true
        end
        expect(usage_error).to be(:==, true)
      end
    end

    it "raises Error for a second block after the END" do
      double = ClientCertVectors::BLOCK1 + ClientCertVectors::BLOCK2
      usage_error = false
      begin
        Fast::ClientCert.pem_to_field(double)
      rescue Fast::ClientCert::Error
        usage_error = true
      end
      expect(usage_error).to be(:==, true)
    end

    it "never validates the base64 — a mangled payload becomes a value" do
      mangled = "-----BEGIN CERTIFICATE-----\nnot base64!!\n-----END CERTIFICATE-----\n"
      expect(Fast::ClientCert.pem_to_field(mangled)).to be(:==, ":not base64!!:")
    end

    it "raises TypeError for a non-String" do
      [nil, 5].each do |bad|
        type_error = false
        begin
          Fast::ClientCert.pem_to_field(bad)
        rescue TypeError
          type_error = true
        end
        expect(type_error).to be(:==, true)
      end
    end
  end

  describe ".field_to_pem" do
    it "writes the Appendix A values back to their blocks, exact" do
      expect(Fast::ClientCert.field_to_pem(ClientCertVectors::FIG2)).to be(:==, ClientCertVectors::BLOCK1)
      expect(Fast::ClientCert.field_to_pem(ClientCertVectors::FIG3_MEMBER1)).to be(:==, ClientCertVectors::BLOCK2)
      expect(Fast::ClientCert.field_to_pem(ClientCertVectors::FIG3_MEMBER2)).to be(:==, ClientCertVectors::BLOCK3)
    end

    it "round-trips every appendix value both ways" do
      [ClientCertVectors::FIG2, ClientCertVectors::FIG3_MEMBER1, ClientCertVectors::FIG3_MEMBER2].each do |value|
        expect(Fast::ClientCert.pem_to_field(Fast::ClientCert.field_to_pem(value))).to be(:==, value)
      end
    end

    it "wraps the base64 at 64 characters per line (RFC 7468)" do
      wrap = Fast::ClientCert.field_to_pem(":#{'A' * 68}:")
      expected = ["-----BEGIN CERTIFICATE-----", "A" * 64, "A" * 4, "-----END CERTIFICATE-----"]
      expect(wrap.lines.map(&:chomp)).to be(:==, expected)
    end

    it "raises Error for a value that is not a whole base64 item" do
      ["aGVsbG8=", ":aGVsbG8=", "aGVsbG8=:", ":", ":aGVsbG8=:;q=1", ":a===:", ":aGVsbG=:"].each do |bad|
        usage_error = false
        begin
          Fast::ClientCert.field_to_pem(bad)
        rescue Fast::ClientCert::Error
          usage_error = true
        end
        expect(usage_error).to be(:==, true)
      end
    end

    it "raises TypeError for a non-String" do
      type_error = false
      begin
        Fast::ClientCert.field_to_pem(5)
      rescue TypeError
        type_error = true
      end
      expect(type_error).to be(:==, true)
    end
  end

  describe ".pems_to_field" do
    it "joins the chain pair into the Figure 3 value" do
      blocks = [ClientCertVectors::BLOCK2, ClientCertVectors::BLOCK3]
      expect(Fast::ClientCert.pems_to_field(blocks)).to be(:==, ClientCertVectors::FIG3)
    end

    it "converts a one-block Array to the single item value" do
      expect(Fast::ClientCert.pems_to_field([ClientCertVectors::BLOCK1])).to be(:==, ClientCertVectors::FIG2)
    end

    it "raises Error for an empty Array" do
      usage_error = false
      begin
        Fast::ClientCert.pems_to_field([])
      rescue Fast::ClientCert::Error
        usage_error = true
      end
      expect(usage_error).to be(:==, true)
    end

    it "raises TypeError for a non-Array" do
      [nil, 5, "block"].each do |bad|
        type_error = false
        begin
          Fast::ClientCert.pems_to_field(bad)
        rescue TypeError
          type_error = true
        end
        expect(type_error).to be(:==, true)
      end
    end
  end

  describe ".field_to_pems" do
    it "splits the Figure 3 value into its blocks" do
      expect(Fast::ClientCert.field_to_pems(ClientCertVectors::FIG3)).to be(:==, [ClientCertVectors::BLOCK2, ClientCertVectors::BLOCK3])
    end

    it "parses the separator with or without the canonical space" do
      tight = "#{ClientCertVectors::FIG3_MEMBER1},#{ClientCertVectors::FIG3_MEMBER2}"
      expect(Fast::ClientCert.field_to_pems(tight)).to be(:==, [ClientCertVectors::BLOCK2, ClientCertVectors::BLOCK3])
    end

    it "answers no blocks for the empty value" do
      expect(Fast::ClientCert.field_to_pems("")).to be(:==, [])
    end

    it "raises Error for a member that is not a whole base64 item" do
      [":aGVsbG8=:, 5", ":", ":aGVsbG8=:,"].each do |bad|
        usage_error = false
        begin
          Fast::ClientCert.field_to_pems(bad)
        rescue Fast::ClientCert::Error
          usage_error = true
        end
        expect(usage_error).to be(:==, true)
      end
    end

    it "splits on parameter-aware member boundaries (9651 4.2)" do
      # A comma inside a quoted parameter value is content, not a
      # separator: the param-carrying member converts whole, the
      # member that follows it is its own member, and the fragment an
      # error names is a real member's value, never a split artifact.
      field = ':aGVsbG8=:;a="x,y", :QUJDRA==:'.dup
      blocks = Fast::ClientCert.field_to_pems(field)
      expect(blocks).to be(:==, Fast::ClientCert.field_to_pems(":aGVsbG8=:, :QUJDRA==:"))
      rebuilt = Fast::ClientCert.pems_to_field(blocks)
      expect(rebuilt).to be(:==, ":aGVsbG8=:, :QUJDRA==:")
      expect(Fast::ClientCert::Chain.parse(field).ders)
        .to be(:==, Fast::ClientCert::Chain.parse(rebuilt).ders)
      error = false
      begin
        Fast::ClientCert.field_to_pems(':aGVsbG8=:;a="x,y", :QUJD=:'.dup)
      rescue Fast::ClientCert::Error => e
        error = e
      end
      expect(error).to be(:kind_of?, Fast::ClientCert::Error)
    end

    it "raises TypeError for a non-String" do
      type_error = false
      begin
        Fast::ClientCert.field_to_pems(nil)
      rescue TypeError
        type_error = true
      end
      expect(type_error).to be(:==, true)
    end
  end

  describe "the composition with the field classes" do
    it "parses the surgically converted chain value" do
      blocks = [ClientCertVectors::BLOCK2, ClientCertVectors::BLOCK3]
      field = Fast::ClientCert.pems_to_field(blocks)
      expect(Fast::ClientCert::Chain.parse(field).to_s).to be(:==, ClientCertVectors::FIG3)
    end

    it "parses the surgically converted item value" do
      field = Fast::ClientCert.pem_to_field(ClientCertVectors::BLOCK1)
      expect(Fast::ClientCert::Cert.parse(field).to_s).to be(:==, ClientCertVectors::FIG2)
    end
  end
end
