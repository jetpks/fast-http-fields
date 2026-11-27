# frozen_string_literal: true

require "fast/digest"
require "digest"

describe Fast::Digest do
  # Appendix D's input: no trailing LF.
  def hello
    %({"hello": "world"})
  end

  describe "ALGORITHMS" do
    it "carries Table 2's eight keys in order" do
      expected = %w[sha-512 sha-256 md5 sha unixsum unixcksum adler crc32c]
      expect(Fast::Digest::ALGORITHMS.keys).to be(:==, expected)
    end

    it "carries the Active and Deprecated statuses" do
      expect(Fast::Digest.status("sha-512")).to be(:==, "Active")
      expect(Fast::Digest.status("sha-256")).to be(:==, "Active")
      %w[md5 sha unixsum unixcksum adler crc32c].each do |key|
        expect(Fast::Digest.status(key)).to be(:==, "Deprecated")
      end
    end

    it "carries a description per entry, as frozen data" do
      Fast::Digest::ALGORITHMS.each_value do |entry|
        expect(entry.frozen?).to be(:==, true)
        expect(entry["status"]).to be(:kind_of?, String)
        expect(entry["description"]).to be(:kind_of?, String)
        expect(entry["description"].empty?).to be(:==, false)
      end
      expect(Fast::Digest::ALGORITHMS.frozen?).to be(:==, true)
      expect(Fast::Digest::ALGORITHMS["sha-512"]["description"]).to be(:==, "The SHA-512 algorithm.")
    end
  end

  describe "the registry lookups" do
    it "answers registered?, active?, deprecated? and status with unknown passthrough" do
      expect(Fast::Digest.registered?("crc32c")).to be(:==, true)
      expect(Fast::Digest.registered?("sha-3")).to be(:==, false)
      expect(Fast::Digest.active?("sha-256")).to be(:==, true)
      expect(Fast::Digest.active?("md5")).to be(:==, false)
      expect(Fast::Digest.active?("sha-3")).to be(:==, false)
      expect(Fast::Digest.deprecated?("md5")).to be(:==, true)
      expect(Fast::Digest.deprecated?("sha-256")).to be(:==, false)
      expect(Fast::Digest.deprecated?("sha-3")).to be(:==, false)
      expect(Fast::Digest.status("sha-3")).to be(:==, nil)
    end

    it "answers computable? for the stdlib set, the checksum set and unknown keys" do
      %w[sha-256 sha-512 md5 sha].each { |key| expect(Fast::Digest.computable?(key)).to be(:==, true) }
      %w[unixsum unixcksum adler crc32c sha-3].each { |key| expect(Fast::Digest.computable?(key)).to be(:==, false) }
    end
  end

  describe ".compute" do
    it "answers exactly the stdlib bytes, frozen and binary" do
      expect(Fast::Digest.compute("sha-256", hello)).to be(:==, Digest::SHA256.digest(hello))
      expect(Fast::Digest.compute("sha-512", hello)).to be(:==, Digest::SHA512.digest(hello))
      expect(Fast::Digest.compute("md5", hello)).to be(:==, Digest::MD5.digest(hello))
      expect(Fast::Digest.compute("sha", hello)).to be(:==, Digest::SHA1.digest(hello))
      value = Fast::Digest.compute("sha-256", hello)
      expect(value.encoding).to be(:==, Encoding::ASCII_8BIT)
      expect(value.frozen?).to be(:==, true)
    end

    it "hashes the input bytewise whatever its encoding" do
      expect(Fast::Digest.compute("sha-256", hello.dup.force_encoding(Encoding::UTF_8)))
        .to be(:==, Digest::SHA256.digest(hello))
    end

    it "raises Error for the checksum entries and unknown keys" do
      %w[unixsum unixcksum adler crc32c].each do |key|
        error = nil
        begin
          Fast::Digest.compute(key, "x")
        rescue Fast::Digest::Error => e
          error = e
        end
        expect(error).to be(:kind_of?, Fast::Digest::Error)
        expect(Fast::Digest.registered?(key)).to be(:==, true)
        expect(Fast::Digest.computable?(key)).to be(:==, false)
      end
      error = nil
      begin
        Fast::Digest.compute("sha-3", "x")
      rescue Fast::Digest::Error => e
        error = e
      end
      expect(error).to be(:kind_of?, Fast::Digest::Error)
      expect(Fast::Digest.registered?("sha-3")).to be(:==, false)
    end

    it "raises TypeError for a non-String input" do
      [5, nil, :sym].each do |wrong|
        expect { Fast::Digest.compute("sha-256", wrong) }.to raise_exception(::TypeError)
      end
    end
  end

  describe "the error hierarchy" do
    it "is the family shape" do
      expect(Fast::Digest::Error < StandardError).to be(:==, true)
      expect(Fast::Digest::ParseError < Fast::Digest::Error).to be(:==, true)
      expect(Fast::Digest::SerializeError < Fast::Digest::Error).to be(:==, true)
      expect(Fast::Digest::ParseError.new("message", 7).offset).to be(:==, 7)
      expect(Fast::Digest::SerializeError.new("message", 0).offset).to be(:==, 0)
    end
  end
end
