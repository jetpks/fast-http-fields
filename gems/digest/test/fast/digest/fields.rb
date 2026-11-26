# frozen_string_literal: true

require "fast/digest"
require "digest"

describe Fast::Digest do
  # The ParseError a strict parse raised, or nil — the frozen offset
  # pins are read off it.
  def strict_error_of(field, input)
    field.parse!(input)
    nil
  rescue Fast::Digest::ParseError => e
    e
  end

  # The SerializeError a construction raised, or nil.
  def construction_error_of(field, members)
    field.new(members)
    nil
  rescue Fast::Digest::SerializeError => e
    e
  end

  # Appendix D's input has no trailing LF, unlike appendix B's bodies —
  # the two appendixes hash different inputs.
  def hello
    %({"hello": "world"})
  end

  def hello_lf
    %({"hello": "world"}\n)
  end

  describe ".parse" do
    it "reads the B.1 value, content and repr agreeing" do
      b1 = "sha-256=:RK/0qy18MlBSVnWgjwz6lZEWjP/lF5HF9bvEF8FabDg=:"
      expect(Fast::Digest::ReprDigest.parse(b1)["sha-256"]).to be(:==, Digest::SHA256.digest(hello_lf))
      expect(Fast::Digest::ContentDigest.parse(b1)["sha-256"]).to be(:==, Digest::SHA256.digest(hello_lf))
      expect(Fast::Digest::ReprDigest.parse(b1).to_s).to be(:==, b1)
    end

    it "reads the B.2 empty-content digest" do
      field = Fast::Digest::ContentDigest.parse("sha-256=:47DEQpj8HBSa+/TImW+5JCeuQeRkm5NMpJWZG3hSuFU=:")
      expect(field["sha-256"]).to be(:==, Digest::SHA256.digest(""))
    end

    it "reads the B.3 partial-content digest" do
      field = Fast::Digest::ContentDigest.parse("sha-256=:jjcgBDWNAtbYUXI37CVG3gRuGOAjaaDRGpIUFsdyepQ=:")
      expect(field["sha-256"]).to be(:==, Digest::SHA256.digest(%("world"}\n)))
    end

    it "reads the sha-512 example of 2, 3 and C.2" do
      sha512 = "sha-512=:YMAam51Jz/jOATT6/zvHrLVgOYTGFy1d6GJiOHTohq4yP+pgk4vf2aCsyRZOtw8MjkM7iw7yZ/WkppmM44T3qg==:"
      expect(Fast::Digest::ContentDigest.parse(sha512)["sha-512"]).to be(:==, Digest::SHA512.digest(hello_lf))
      expect(Fast::Digest::ReprDigest.parse(sha512)["sha-512"]).to be(:==, Digest::SHA512.digest(hello_lf))
    end

    it "reads the B.7, B.8 and B.9 request digest" do
      field = Fast::Digest::ReprDigest.parse("sha-256=:mEkdbO7Srd9LIOegftO0aBX+VPTVz7/CSHes2Z27gc4=:")
      expect(field["sha-256"]).to be(:==, Digest::SHA256.digest(%({"title": "New Title"}\n)))
    end

    it "reads the B.7 and B.9 response digest" do
      body = "{\n  \"id\": \"123\",\n  \"title\": \"New Title\"\n}\n"
      field = Fast::Digest::ReprDigest.parse("sha-256=:uVSlinTTdQUwm2On4k8TJUikGN1bf/Ds8WPX4oe0h9I=:")
      expect(field["sha-256"]).to be(:==, Digest::SHA256.digest(body))
    end

    it "reads the B.8 response digest" do
      body = "{\n  \"status\": \"created\",\n  \"id\": \"123\",\n  \"ts\": 1569327729,\n" \
             "  \"instance\": \"/books/123\"\n}\n"
      field = Fast::Digest::ReprDigest.parse("sha-256=:yXIGDTN5VrfoyisKlXgRKUHHMs35SNtyC3szSz1dbO8=:")
      expect(field["sha-256"]).to be(:==, Digest::SHA256.digest(body))
    end

    it "reads the B.10 error digest" do
      body = "{\n  \"title\": \"Not Found\",\n  \"detail\": \"Cannot PATCH a non-existent resource\",\n" \
             "  \"status\": 404\n}\n"
      field = Fast::Digest::ReprDigest.parse("sha-256=:EXB0S2VF2H7ijkAVJkH1Sm0pBho0iDZcvVUHHXTTZSA=:")
      expect(field["sha-256"]).to be(:==, Digest::SHA256.digest(body))
    end

    it "reads the B.5, B.11 and C.1 erratum padding to the same bytes" do
      b1 = "sha-256=:RK/0qy18MlBSVnWgjwz6lZEWjP/lF5HF9bvEF8FabDg=:"
      b11 = "sha-256=:RK/0qy18MlBSVnWgjwz6lZEWjP/lF5HF9bvEF8FabDg==:"
      field = Fast::Digest::ReprDigest.parse(b11)
      expect(field["sha-256"]).to be(:==, Digest::SHA256.digest(hello_lf))
      expect(field.to_s).to be(:==, b1)
    end

    it "reads the Appendix D md5 and sha digests (Deprecated algorithms)" do
      md5 = Fast::Digest::ReprDigest.parse("md5=:Sd/dVLAcvNLSq16eXua5uQ==:")
      sha = Fast::Digest::ReprDigest.parse("sha=:07CavjDP4u3/TungoUHJO/Wzr4c=:")
      expect(md5["md5"]).to be(:==, Digest::MD5.digest(hello))
      expect(sha["sha"]).to be(:==, Digest::SHA1.digest(hello))
    end

    it "carries the Appendix D checksum values bytewise, unverified" do
      checksums = {
        "unixsum" => ["GQU=", "1905"],
        "unixcksum" => ["7zsHAA==", "ef3b0700"],
        "adler" => ["OZkGFw==", "39990617"],
        "crc32c" => ["Q3lHIA==", "43794720"]
      }
      checksums.each do |key, (wire, hex)|
        value = Fast::Digest::ReprDigest.parse("#{key}=:#{wire}:")[key]
        expect(value.unpack1("H*")).to be(:==, hex)
      end
    end

    it "passes the B.6 quoted Brotli values through bytewise" do
      quoted = "sha-256=:d435Qo+nKZ+gLcUHn7GQtQ72hiBVAgqoLsZnZPiTGPk=:, " \
               "sha-512=:db7fdBbgZMgX1Wb2MjA8zZj+rSNgfmDCEEXM8qLWfpfoNY0sCpHAzZbj09X1/7HAb7Od5Qfto4QpuBsFbUO3dQ==:"
      field = Fast::Digest::ReprDigest.parse(quoted)
      expect(field.keys).to be(:==, %w[sha-256 sha-512])
      expect(field.to_s).to be(:==, quoted)
    end

    it "is fail-closed on any member violating the Byte Sequence constraint" do
      ["sha-256=5", "sha-256=hello", %(sha-256="abc"), "sha-256=?0", "sha-256", "sha-256=(a b)"].each do |bad|
        expect(Fast::Digest::ReprDigest.parse(bad).empty?).to be(:==, true)
        expect(Fast::Digest::ContentDigest.parse(bad).empty?).to be(:==, true)
      end
    end

    it "is fail-closed on the whole field when one member is bad" do
      expect(Fast::Digest::ReprDigest.parse("sha-512=:AAAA:, md5=5").empty?).to be(:==, true)
      expect(Fast::Digest::ReprDigest.parse("md5=5, sha-512=:AAAA:").empty?).to be(:==, true)
    end

    it "answers the empty value for a malformed field and for the empty Dictionary" do
      expect(Fast::Digest::ReprDigest.parse("!!").empty?).to be(:==, true)
      expect(Fast::Digest::ReprDigest.parse("!!").to_s).to be(:==, "")
      expect(Fast::Digest::ReprDigest.parse("").empty?).to be(:==, true)
      expect(Fast::Digest::ReprDigest.parse("").to_s).to be(:==, "")
    end

    it "passes unknown algorithm keys through" do
      expect(Fast::Digest::ReprDigest.parse("sha-3=:AAAA:")["sha-3"].bytesize).to be(:==, 3)
      expect(Fast::Digest::WantReprDigest.parse("sha-3=5")["sha-3"]).to be(:==, 5)
    end

    it "preserves SFV parameters and re-emits them" do
      b1 = "sha-256=:RK/0qy18MlBSVnWgjwz6lZEWjP/lF5HF9bvEF8FabDg=:;q=1"
      field = Fast::Digest::ReprDigest.parse(b1)
      expect(field.to_s).to be(:==, b1)
      expect(field["sha-256"]).to be(:==, Digest::SHA256.digest(hello_lf))
    end

    it "combines an Array of field lines and applies last-wins" do
      combined = Fast::Digest::ContentDigest.parse(["sha-256=:AAAA:", "md5=:BBBB:"])
      expect(combined.keys).to be(:==, %w[sha-256 md5])
      expect(combined.to_s).to be(:==, "sha-256=:AAAA:, md5=:BBBB:")
      last = Fast::Digest::ContentDigest.parse(["sha-256=:AAAA:", "sha-256=:CCCC:"])
      expect(last.keys).to be(:==, ["sha-256"])
      expect(last["sha-256"].unpack1("H*")).to be(:==, "082082")
    end

    it "answers frozen value objects with frozen bytes" do
      field = Fast::Digest::ReprDigest.parse("sha-256=:RK/0qy18MlBSVnWgjwz6lZEWjP/lF5HF9bvEF8FabDg=:")
      expect(field.frozen?).to be(:==, true)
      expect(field.members.frozen?).to be(:==, true)
      expect(field.keys.frozen?).to be(:==, true)
      expect(field["sha-256"].frozen?).to be(:==, true)
      expect(field["sha-256"].encoding).to be(:==, Encoding::ASCII_8BIT)
    end

    it "raises TypeError for a non-String, non-Array input" do
      [42, nil, 3.14, :sym, {}].each do |wrong|
        expect { Fast::Digest::ReprDigest.parse(wrong) }.to raise_exception(::TypeError)
        expect { Fast::Digest::WantContentDigest.parse(wrong) }.to raise_exception(::TypeError)
      end
      expect { Fast::Digest::ReprDigest.parse(["sha-256=:AAAA:", 42]) }.to raise_exception(::TypeError)
    end
  end

  describe ".parse (the preference fields)" do
    it "reads the section 4 examples for both Want fields" do
      want = Fast::Digest::WantReprDigest.parse("sha-512=3, sha-256=10, unixsum=0")
      expect(want.keys).to be(:==, %w[sha-512 sha-256 unixsum])
      expect(want["sha-512"]).to be(:==, 3)
      expect(want["sha-256"]).to be(:==, 10)
      expect(want["unixsum"]).to be(:==, 0)
      expect(want.to_s).to be(:==, "sha-512=3, sha-256=10, unixsum=0")
      expect(Fast::Digest::WantReprDigest.parse("sha-256=1")["sha-256"]).to be(:==, 1)
      expect(Fast::Digest::WantContentDigest.parse("sha-256=1")["sha-256"]).to be(:==, 1)
      expect(Fast::Digest::WantContentDigest.parse("sha-512=3, sha-256=10, unixsum=0")["unixsum"]).to be(:==, 0)
    end

    it "reads the C.1 request preferences" do
      want = Fast::Digest::WantReprDigest.parse("sha-256=3, sha=10")
      expect(want["sha"]).to be(:==, 10)
      expect(want.to_s).to be(:==, "sha-256=3, sha=10")
    end

    it "reads the 0 and 10 boundaries" do
      expect(Fast::Digest::WantReprDigest.parse("sha-256=0")["sha-256"]).to be(:==, 0)
      expect(Fast::Digest::WantReprDigest.parse("sha-256=10")["sha-256"]).to be(:==, 10)
    end

    it "is fail-closed on any member outside Integer 0..10" do
      bad_members = ["sha-256=:AAAA:", "sha-256=-1", "sha-256=11", "sha-256=3.5", "sha-256=fast", "sha-256=?0"]
      (bad_members + ["sha-256", "sha-256=(a b)"]).each do |bad|
        expect(Fast::Digest::WantReprDigest.parse(bad).empty?).to be(:==, true)
        expect(Fast::Digest::WantContentDigest.parse(bad).empty?).to be(:==, true)
      end
      expect(Fast::Digest::WantReprDigest.parse("sha-512=3, sha-256=11").empty?).to be(:==, true)
      expect(Fast::Digest::WantReprDigest.parse("!!").empty?).to be(:==, true)
      expect(Fast::Digest::WantReprDigest.parse("").empty?).to be(:==, true)
    end
  end

  describe ".parse!" do
    it "wraps the SFV Dictionary failure with its message and offset" do
      error = strict_error_of(Fast::Digest::ReprDigest, "!!")
      expect(error).to be(:kind_of?, Fast::Digest::ParseError)
      expect(error.offset).to be(:==, 0)
      expect(error.message.length).to be(:>, 0)
    end

    it "positions the Integrity member errors at the value, frozen pins" do
      { "sha-256=5" => 8, "sha-256" => 7, "md5=:AAAA:, sha-256=5" => 20 }.each do |input, offset|
        error = strict_error_of(Fast::Digest::ReprDigest, input)
        expect(error.offset).to be(:==, offset)
      end
      error = strict_error_of(Fast::Digest::ReprDigest, ["sha-256=:AAAA:", "sha-256=5"])
      expect(error.offset).to be(:==, 24)
    end

    it "positions the preference member errors at the value, frozen pins" do
      { "sha-256=11" => 8, "sha-256=?0" => 8, "unixsum=-1" => 8 }.each do |input, offset|
        error = strict_error_of(Fast::Digest::WantReprDigest, input)
        expect(error.offset).to be(:==, offset)
      end
    end

    it "names the member, the field and the required shape" do
      error = strict_error_of(Fast::Digest::WantReprDigest, "sha-256=11")
      expect(error.message).to be(:include?, "sha-256")
      expect(error.message).to be(:include?, "Integer 0..10")
      error = strict_error_of(Fast::Digest::ReprDigest, "sha-256=5")
      expect(error.message).to be(:include?, "Byte Sequence")
    end

    it "raises at the effective, last-wins member" do
      expect(strict_error_of(Fast::Digest::ReprDigest, "sha-256=:AAAA:, sha-256=5").offset).to be(:==, 24)
      expect(strict_error_of(Fast::Digest::WantReprDigest, "sha-256=3, sha-256=11").offset).to be(:==, 19)
    end

    it "returns the strict view of a valid field, parameters preserved" do
      b1 = "sha-256=:RK/0qy18MlBSVnWgjwz6lZEWjP/lF5HF9bvEF8FabDg=:;q=1"
      field = Fast::Digest::ReprDigest.parse!(b1)
      expect(field.to_s).to be(:==, b1)
      expect(field["sha-256"]).to be(:==, Digest::SHA256.digest(hello_lf))
      want = Fast::Digest::WantReprDigest.parse!("sha-512=3, sha-256=10, unixsum=0")
      expect(want.to_s).to be(:==, "sha-512=3, sha-256=10, unixsum=0")
    end

    it "raises TypeError for a wrong input type, as parse" do
      [42, nil, :sym].each do |wrong|
        expect { Fast::Digest::ReprDigest.parse!(wrong) }.to raise_exception(::TypeError)
      end
    end
  end

  describe ".valid?" do
    it "mirrors the strict parse with a boolean" do
      b1 = "sha-256=:RK/0qy18MlBSVnWgjwz6lZEWjP/lF5HF9bvEF8FabDg=:"
      expect(Fast::Digest::ReprDigest.valid?(b1)).to be(:==, true)
      expect(Fast::Digest::WantReprDigest.valid?("sha-512=3, sha-256=10, unixsum=0")).to be(:==, true)
      expect(Fast::Digest::ReprDigest.valid?("")).to be(:==, true)
      expect(Fast::Digest::WantReprDigest.valid?("")).to be(:==, true)
      expect(Fast::Digest::ReprDigest.valid?("!!")).to be(:==, false)
      expect(Fast::Digest::ReprDigest.valid?("sha-256=5")).to be(:==, false)
      expect(Fast::Digest::WantReprDigest.valid?("sha-256=11")).to be(:==, false)
      expect(Fast::Digest::WantReprDigest.valid?("sha-256=fast")).to be(:==, false)
      expect(Fast::Digest::ReprDigest.valid?(5)).to be(:==, false)
      expect(Fast::Digest::WantContentDigest.valid?(nil)).to be(:==, false)
    end
  end

  describe "the value objects" do
    it "builds the canonical wire form from a construction" do
      b1 = "sha-256=:RK/0qy18MlBSVnWgjwz6lZEWjP/lF5HF9bvEF8FabDg=:"
      field = Fast::Digest::ContentDigest.new("sha-256" => Digest::SHA256.digest(hello_lf))
      expect(field.to_s).to be(:==, b1)
      appendix_d = "sha-256=:X48E9qOokqqrvdts8nOJRJN3OWDUoyWxBf7kbu9DBPE=:, md5=:Sd/dVLAcvNLSq16eXua5uQ==:"
      two = Fast::Digest::ContentDigest.new(
        "sha-256" => Digest::SHA256.digest(hello), "md5" => Digest::MD5.digest(hello)
      )
      expect(two.to_s).to be(:==, appendix_d)
      expect(Fast::Digest::WantReprDigest.new("sha-256" => 10).to_s).to be(:==, "sha-256=10")
      expect(Fast::Digest::WantContentDigest.new("sha-256" => 0).to_s).to be(:==, "sha-256=0")
      expect(Fast::Digest::ReprDigest.new({}).to_s).to be(:==, "")
      expect(Fast::Digest::WantReprDigest.new({}).to_s).to be(:==, "")
    end

    it "freezes the value Strings in place and the object itself" do
      digest = Digest::SHA256.digest("x").dup
      field = Fast::Digest::ContentDigest.new("sha-256" => digest)
      expect(digest.frozen?).to be(:==, true)
      expect(field.frozen?).to be(:==, true)
      expect(field.members.frozen?).to be(:==, true)
    end

    it "raises SerializeError for a non-byte-sequence Integrity value" do
      [5, 3.5, true, nil, "utf8tag".dup, "abc", Fast::SFV::Token.new("tok")].each do |bad|
        error = construction_error_of(Fast::Digest::ReprDigest, "sha-256" => bad)
        expect(error).to be(:kind_of?, Fast::Digest::SerializeError)
      end
    end

    it "raises SerializeError for a non-Integer or out-of-range preference" do
      [11, -1, 3.5, "10", true, nil].each do |bad|
        error = construction_error_of(Fast::Digest::WantReprDigest, "sha-256" => bad)
        expect(error).to be(:kind_of?, Fast::Digest::SerializeError)
      end
    end

    it "raises SerializeError for a member key outside the key grammar" do
      ["SHA-256", "sha 256", 5, nil].each do |bad|
        error = construction_error_of(Fast::Digest::ReprDigest, bad => Digest::SHA256.digest("x"))
        expect(error).to be(:kind_of?, Fast::Digest::SerializeError)
      end
      expect(construction_error_of(Fast::Digest::ReprDigest, "not a hash"))
        .to be(:kind_of?, Fast::Digest::SerializeError)
    end

    it "answers the reader set" do
      want = Fast::Digest::WantReprDigest.parse("sha-512=3, sha-256=10")
      expect(want.size).to be(:==, 2)
      expect(want.key?("sha-512")).to be(:==, true)
      expect(want.key?("md5")).to be(:==, false)
      expect(want["md5"]).to be(:==, nil)
      expect(want.empty?).to be(:==, false)
      pairs = []
      want.each { |key, value| pairs << [key, value] }
      expect(pairs).to be(:==, [["sha-512", 3], ["sha-256", 10]])
      expect(want.members["sha-512"]).to be(:kind_of?, Fast::SFV::Item)
      expect(Fast::Digest::ReprDigest.new({}).empty?).to be(:==, true)
    end

    it "compares by canonical wire form within the field class" do
      b1 = "sha-256=:RK/0qy18MlBSVnWgjwz6lZEWjP/lF5HF9bvEF8FabDg=:"
      repr = Fast::Digest::ReprDigest.parse(b1)
      expect(repr == Fast::Digest::ReprDigest.of("sha-256", hello_lf)).to be(:==, true)
      expect(repr.eql?(Fast::Digest::ReprDigest.parse(b1))).to be(:==, true)
      expect(repr.hash).to be(:==, Fast::Digest::ReprDigest.parse(b1).hash)
      expect(repr == Fast::Digest::ContentDigest.parse(b1)).to be(:==, false)
      expect(Fast::Digest::WantReprDigest.parse("sha-256=1") == Fast::Digest::WantContentDigest.parse("sha-256=1"))
        .to be(:==, false)
    end

    it "inspects with the class name and the wire form" do
      b1 = "sha-256=:RK/0qy18MlBSVnWgjwz6lZEWjP/lF5HF9bvEF8FabDg=:"
      expect(Fast::Digest::ReprDigest.parse(b1).inspect).to be(:==, "#<Fast::Digest::ReprDigest #{b1}>")
      expect(Fast::Digest::ReprDigest.new({}).inspect).to be(:==, "#<Fast::Digest::ReprDigest>")
      inspected = Fast::Digest::WantReprDigest.parse("sha-256=1").inspect
      expect(inspected).to be(:==, "#<Fast::Digest::WantReprDigest sha-256=1>")
    end
  end

  describe ".of" do
    it "computes, emits, parses and compares bytewise for all four algorithms" do
      %w[sha-256 sha-512 md5 sha].each do |key|
        digest = Fast::Digest.compute(key, hello)
        emitted = Fast::Digest::ReprDigest.new(key => digest).to_s
        expect(Fast::Digest::ReprDigest.parse(emitted)[key]).to be(:==, digest)
      end
    end

    it "answers the B.1 wire form for repr and the B.2 for empty content" do
      b1 = "sha-256=:RK/0qy18MlBSVnWgjwz6lZEWjP/lF5HF9bvEF8FabDg=:"
      empty = "sha-256=:47DEQpj8HBSa+/TImW+5JCeuQeRkm5NMpJWZG3hSuFU=:"
      expect(Fast::Digest::ReprDigest.of("sha-256", hello_lf).to_s).to be(:==, b1)
      expect(Fast::Digest::ContentDigest.of("sha-256", "").to_s).to be(:==, empty)
      expect(Fast::Digest::ContentDigest.of("md5", hello)["md5"]).to be(:==, Digest::MD5.digest(hello))
    end

    it "raises Error for a key compute refuses, and TypeError for a non-String input" do
      %w[crc32c adler unixsum unixcksum sha-3].each do |key|
        expect { Fast::Digest::ContentDigest.of(key, "x") }.to raise_exception(Fast::Digest::Error)
        expect { Fast::Digest::ReprDigest.of(key, "x") }.to raise_exception(Fast::Digest::Error)
      end
      expect { Fast::Digest::ReprDigest.of("sha-256", 5) }.to raise_exception(::TypeError)
      expect { Fast::Digest::ReprDigest.of("sha-256", nil) }.to raise_exception(::TypeError)
    end

    it "carries no .of on the preference fields" do
      expect(Fast::Digest::WantContentDigest.respond_to?(:of)).to be(:==, false)
      expect(Fast::Digest::WantReprDigest.respond_to?(:of)).to be(:==, false)
    end
  end
end
