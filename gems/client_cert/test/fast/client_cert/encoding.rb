# frozen_string_literal: true

require "fast/client_cert"

# The two input classes the field's own vectors never modeled: a String
# whose encoding is not ASCII-compatible (UTF-16 and UTF-32 — RFC 9651
# 4.2 step 1 fails the whole field value, so neither the Item nor the
# List ever parses), and an Array of field lines whose encodings cannot
# combine (RFC 9651 4.2 step 2 rejects the line at its start in the
# combined value). The recipient semantics hold on both, for the Item
# field and the List field alike: Cert's lenient parse answers nil (no
# certificate — RFC 9440 4's absent field), Chain's the empty value,
# the strict parse wraps the substrate failure with its message and
# byte offset preserved, and the mirror answers false. Never
# NoMethodError, never Encoding::CompatibilityError. Every pin below is
# a measured behavior.
CLIENT_CERT_NON_ASCII_ENCODINGS = %w[UTF-16LE UTF-16BE UTF-32LE UTF-32BE].freeze
CLIENT_CERT_MIXED_LINES = [":aGVsbG8=:", ":d29ybGQ=:".dup.force_encoding("UTF-32BE")].freeze

describe "the encoding boundaries" do
  # The ParseError a strict parse raised, or nil — the frozen offset
  # pins are read off it. Both fields raise Fast::ClientCert's class.
  def strict_error_of(field, input)
    field.parse!(input)
    nil
  rescue Fast::ClientCert::ParseError => e
    e
  end

  describe ".parse" do
    it "answers nil for Cert and the empty value for Chain for every non-ASCII-compatible encoding" do
      CLIENT_CERT_NON_ASCII_ENCODINGS.each do |name|
        expect(Fast::ClientCert::Cert.parse("1".encode(name))).to be(:==, nil)
        chain = Fast::ClientCert::Chain.parse("1".encode(name))
        expect(chain.empty?).to be(:==, true)
        expect(chain.to_s).to be(:==, "")
      end
    end

    it "answers nil and the empty value for lines that cannot combine" do
      expect(Fast::ClientCert::Cert.parse(CLIENT_CERT_MIXED_LINES)).to be(:==, nil)
      chain = Fast::ClientCert::Chain.parse(CLIENT_CERT_MIXED_LINES)
      expect(chain.empty?).to be(:==, true)
      expect(chain.to_s).to be(:==, "")
    end
  end

  describe ".parse!" do
    it "wraps the item failure for Cert and the list failure for Chain" do
      error = strict_error_of(Fast::ClientCert::Cert, "1".encode("UTF-16LE"))
      expect(error).to be(:kind_of?, Fast::ClientCert::ParseError)
      expect(error.offset).to be(:==, 1)
      error = strict_error_of(Fast::ClientCert::Chain, "1".encode("UTF-16LE"))
      expect(error).to be(:kind_of?, Fast::ClientCert::ParseError)
      expect(error.offset).to be(:==, 2)
    end

    it "wraps the line rejection at the line's start in the combined value" do
      [Fast::ClientCert::Cert, Fast::ClientCert::Chain].each do |field|
        error = strict_error_of(field, CLIENT_CERT_MIXED_LINES)
        expect(error.offset).to be(:==, 12)
      end
    end
  end

  describe ".valid?" do
    it "answers false on both input classes" do
      CLIENT_CERT_NON_ASCII_ENCODINGS.each do |name|
        expect(Fast::ClientCert::Cert.valid?("1".encode(name))).to be(:==, false)
        expect(Fast::ClientCert::Chain.valid?("1".encode(name))).to be(:==, false)
      end
      expect(Fast::ClientCert::Cert.valid?(CLIENT_CERT_MIXED_LINES)).to be(:==, false)
      expect(Fast::ClientCert::Chain.valid?(CLIENT_CERT_MIXED_LINES)).to be(:==, false)
    end
  end

  describe "the no-leak sweep" do
    it "answers only its own ParseError or TypeError" do
      hostile = CLIENT_CERT_NON_ASCII_ENCODINGS.map { |name| ":aGVsbG8=:".encode(name) } + [CLIENT_CERT_MIXED_LINES]
      [Fast::ClientCert::Cert, Fast::ClientCert::Chain].each do |field|
        hostile.each do |input|
          %i[parse parse! valid?].each do |entry|
            leaked = nil
            begin
              field.public_send(entry, input)
            rescue Fast::ClientCert::ParseError, ::TypeError
              nil
            rescue StandardError => e
              leaked = e
            end
            expect(leaked).to be(:==, nil)
          end
        end
      end
    end
  end
end
