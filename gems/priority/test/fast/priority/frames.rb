# frozen_string_literal: true

require "fast/priority"

# Byte assertions go through unpack1("H*") hex strings — never raw
# high-byte string literals: a UTF-8 source cannot carry them, and
# their equality silently fails. Binary payloads are built by packing
# a hex string and appending the ASCII field value.
describe Fast::Priority do
  # The payload for a hex prefix + an ASCII field value.
  def payload(prefix, field_value)
    ([prefix].pack("H*") << field_value)
  end

  describe Fast::Priority::H2 do
    it "carries the frame type of RFC 9218 7.1" do
      expect(Fast::Priority::H2::FRAME_TYPE).to be(:==, 0x10)
    end

    it "encodes the 7.1 payload layout" do
      priority = Fast::Priority.parse("u=1, i")
      encoded = Fast::Priority::H2.encode_payload(5, priority)
      expect(encoded.unpack1("H*")).to be(:==, "00000005753d312c2069")
      expect(encoded.encoding).to be(:==, Encoding::ASCII_8BIT)
    end

    it "decodes the stream identifier, the field value and the priority" do
      frame = Fast::Priority::H2.decode_payload(payload("00000005", "u=1, i"))
      expect(frame).to be(:kind_of?, Fast::Priority::H2::Frame)
      expect(frame.stream_id).to be(:==, 5)
      expect(frame.field_value).to be(:==, "u=1, i")
      expect(frame.field_value.encoding).to be(:==, Encoding::ASCII_8BIT)
      expect(frame.priority.urgency).to be(:==, 1)
      expect(frame.priority.incremental).to be(:==, true)
      expect(frame.error).to be(:nil?)
      expect(frame.frozen?).to be(:==, true)
    end

    it "masks Figure 1's Reserved bit off the stream identifier" do
      frame = Fast::Priority::H2.decode_payload(payload("80000005", "u=1"))
      expect(frame.stream_id).to be(:==, 5)
    end

    it "reads an empty field value as all-defaults, with no error" do
      frame = Fast::Priority::H2.decode_payload(payload("00000005", ""))
      expect(frame.stream_id).to be(:==, 5)
      expect(frame.field_value).to be(:==, "")
      expect(frame.priority.urgency).to be(:==, 3)
      expect(frame.error).to be(:nil?)
    end

    it "surfaces a malformed field value without raising" do
      frame = Fast::Priority::H2.decode_payload(payload("00000005", "!!"))
      expect(frame.stream_id).to be(:==, 5)
      expect(frame.error).to be(:kind_of?, Fast::Priority::ParseError)
      expect(frame.priority.urgency).to be(:==, 3)
    end

    it "keeps a parsed-but-ignored member out of the error" do
      frame = Fast::Priority::H2.decode_payload(payload("00000005", "u=9"))
      expect(frame.error).to be(:nil?)
      expect(frame.priority.urgency).to be(:==, 3)
    end

    it "raises TypeError for a non-String payload" do
      [nil, 42, :sym].each do |wrong|
        expect { Fast::Priority::H2.decode_payload(wrong) }.to raise_exception(::TypeError)
      end
    end

    it "raises a positioned ParseError for a payload shorter than the word" do
      error = nil
      begin
        Fast::Priority::H2.decode_payload(payload("000000", ""))
      rescue Fast::Priority::ParseError => e
        error = e
      end
      expect(error).to be(:kind_of?, Fast::Priority::ParseError)
      expect(error.offset).to be(:==, 3)
    end

    it "raises SerializeError for a non-Parameters field value and an out-of-range identifier" do
      priority = Fast::Priority.parse("u=1, i")
      expect { Fast::Priority::H2.encode_payload(5, "u=1") }.to raise_exception(Fast::Priority::SerializeError)
      expect { Fast::Priority::H2.encode_payload(0x8000_0000, priority) }
        .to raise_exception(Fast::Priority::SerializeError)
      expect { Fast::Priority::H2.encode_payload(-1, priority) }.to raise_exception(Fast::Priority::SerializeError)
    end

    it "refuses to emit a prioritized stream ID of 0" do
      # RFC 9218 §7.1: a received prioritized stream ID of 0x0 is an
      # unconditional connection error of type PROTOCOL_ERROR, so a
      # strict sender never puts one on the wire.
      priority = Fast::Priority.parse("u=1, i")
      error = nil
      begin
        Fast::Priority::H2.encode_payload(0, priority)
      rescue Fast::Priority::SerializeError => e
        error = e
      end
      expect(error).to be(:kind_of?, Fast::Priority::Error)
      expect(error.message).to be(:==, "the prioritized stream ID is an Integer 1..0x7FFFFFFF, never 0 (got Integer)")
      expect(error.offset).to be(:==, 0)
      expect(Fast::Priority::H2.encode_payload(1, priority).unpack1("H*")).to be(:==, "00000001753d312c2069")
    end

    it "round-trips the 31-bit limit" do
      priority = Fast::Priority.parse("u=1, i")
      frame = Fast::Priority::H2.decode_payload(Fast::Priority::H2.encode_payload(0x7FFF_FFFF, priority))
      expect(frame.stream_id).to be(:==, 0x7FFF_FFFF)
      expect(frame.priority.urgency).to be(:==, 1)
      expect(Fast::Priority::H2.encode_payload(0x7FFF_FFFF, priority).unpack1("H*"))
        .to be(:==, "7fffffff753d312c2069")
    end
  end

  describe Fast::Priority::H3 do
    it "carries the frame types of RFC 9218 7.2" do
      expect(Fast::Priority::H3::REQUEST_TYPE).to be(:==, 0xF0700)
      expect(Fast::Priority::H3::PUSH_TYPE).to be(:==, 0xF0701)
    end

    it "encodes the 7.2 payload layout" do
      priority = Fast::Priority.parse("u=1, i")
      encoded = Fast::Priority::H3.encode_payload(4, priority)
      expect(encoded.unpack1("H*")).to be(:==, "04753d312c2069")
      expect(encoded.encoding).to be(:==, Encoding::ASCII_8BIT)
    end

    it "decodes the element identifier, the field value and the priority" do
      frame = Fast::Priority::H3.decode_payload(payload("04", "u=1, i"))
      expect(frame).to be(:kind_of?, Fast::Priority::H3::Frame)
      expect(frame.element_id).to be(:==, 4)
      expect(frame.field_value).to be(:==, "u=1, i")
      expect(frame.field_value.encoding).to be(:==, Encoding::ASCII_8BIT)
      expect(frame.priority.urgency).to be(:==, 1)
      expect(frame.error).to be(:nil?)
      expect(frame.frozen?).to be(:==, true)
    end

    it "encodes the minimal varint at the 1-2 byte boundary (RFC 9000 16)" do
      one = Fast::Priority.parse("u=1")
      expect(Fast::Priority::H3.encode_payload(0, one).unpack1("H*")).to be(:==, "00753d31")
      expect(Fast::Priority::H3.encode_payload(63, one).unpack1("H*")).to be(:==, "3f753d31")
      expect(Fast::Priority::H3.encode_payload(64, one).unpack1("H*")).to be(:==, "4040753d31")
    end

    it "encodes the minimal varint at the 2-4 byte boundary" do
      one = Fast::Priority.parse("u=1")
      expect(Fast::Priority::H3.encode_payload(16_383, one).unpack1("H*")).to be(:==, "7fff753d31")
      expect(Fast::Priority::H3.encode_payload(16_384, one).unpack1("H*")).to be(:==, "80004000753d31")
    end

    it "encodes the minimal varint at the 4-8 byte boundary" do
      one = Fast::Priority.parse("u=1")
      expect(Fast::Priority::H3.encode_payload(0x3FFF_FFFF, one).unpack1("H*")).to be(:==, "bfffffff753d31")
      expect(Fast::Priority::H3.encode_payload(0x4000_0000, one).unpack1("H*"))
        .to be(:==, "c000000040000000753d31")
    end

    it "decodes Appendix A.1's worked examples" do
      expect(Fast::Priority::H3.decode_payload(payload("25", "u=1")).element_id).to be(:==, 37)
      expect(Fast::Priority::H3.decode_payload(payload("7bbd", "u=1")).element_id).to be(:==, 15_293)
      expect(Fast::Priority::H3.decode_payload(payload("9d7f3e7d", "u=1")).element_id).to be(:==, 494_878_333)
      expect(Fast::Priority::H3.decode_payload(payload("c2197c5eff14e88c", "u=1")).element_id)
        .to be(:==, 151_288_809_941_952_652)
    end

    it "decodes a non-minimal varint form (RFC 9000 16)" do
      expect(Fast::Priority::H3.decode_payload(payload("4025", "u=1")).element_id).to be(:==, 37)
      expect(Fast::Priority::H3.decode_payload(payload("4000", "u=1")).element_id).to be(:==, 0)
    end

    it "round-trips the 62-bit limit" do
      one = Fast::Priority.parse("u=1")
      limit = (1 << 62) - 1
      expect(Fast::Priority::H3.decode_payload(Fast::Priority::H3.encode_payload(limit, one)).element_id)
        .to be(:==, limit)
      expect(Fast::Priority::H3.encode_payload(limit, one).unpack1("H*"))
        .to be(:==, "ffffffffffffffff753d31")
    end

    it "reads an empty field value as all-defaults, with no error" do
      frame = Fast::Priority::H3.decode_payload(payload("25", ""))
      expect(frame.element_id).to be(:==, 37)
      expect(frame.field_value).to be(:==, "")
      expect(frame.priority.urgency).to be(:==, 3)
      expect(frame.error).to be(:nil?)
    end

    it "surfaces a malformed field value without raising" do
      frame = Fast::Priority::H3.decode_payload(payload("05", "!!"))
      expect(frame.element_id).to be(:==, 5)
      expect(frame.error).to be(:kind_of?, Fast::Priority::ParseError)
      expect(frame.priority.urgency).to be(:==, 3)
    end

    it "raises TypeError for a non-String payload" do
      [nil, 42, :sym].each do |wrong|
        expect { Fast::Priority::H3.decode_payload(wrong) }.to raise_exception(::TypeError)
      end
    end

    it "raises a positioned ParseError for an empty payload and a truncated varint" do
      empty = nil
      begin
        Fast::Priority::H3.decode_payload("")
      rescue Fast::Priority::ParseError => e
        empty = e
      end
      expect(empty).to be(:kind_of?, Fast::Priority::ParseError)
      expect(empty.offset).to be(:==, 0)

      truncated = nil
      begin
        Fast::Priority::H3.decode_payload(payload("7f", ""))
      rescue Fast::Priority::ParseError => e
        truncated = e
      end
      expect(truncated).to be(:kind_of?, Fast::Priority::ParseError)
      expect(truncated.offset).to be(:==, 1)
    end

    it "raises SerializeError for a non-Parameters field value and an out-of-range identifier" do
      one = Fast::Priority.parse("u=1")
      expect { Fast::Priority::H3.encode_payload(4, "u=1") }.to raise_exception(Fast::Priority::SerializeError)
      expect { Fast::Priority::H3.encode_payload(1 << 62, one) }.to raise_exception(Fast::Priority::SerializeError)
      expect { Fast::Priority::H3.encode_payload(-1, one) }.to raise_exception(Fast::Priority::SerializeError)
    end
  end
end
