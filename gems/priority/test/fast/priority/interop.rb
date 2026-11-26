# frozen_string_literal: true

require "fast/priority"

# Interop with protocol-http2 — the reference HTTP/2 framing stack —
# as a TEST-GROUP peer wired in this gem's own bundle
# (gems/priority/gems.rb), never a runtime dependency. Under the
# monorepo root bundle the peer is absent and this suite contributes
# no assertions (the skip-when-unwired precedent); run it from
# gems/priority with the peer cache staged at the repo root:
#
#   BUNDLE_CACHE_PATH=../../vendor/priority-cache \
#     BUNDLE_GEMFILE=gems.rb bundle install --local
#   BUNDLE_CACHE_PATH=../../vendor/priority-cache \
#     BUNDLE_GEMFILE=gems.rb bundle exec sus test/fast/priority/interop.rb
begin
  require "protocol/http2"
rescue LoadError
  # protocol-http2 absent (the root bundle / CI) — the interop suite skips.
else
  require "stringio"

  describe "protocol-http2 interop" do
    def write_frame(frame)
      io = StringIO.new(+"")
      Protocol::HTTP2::Framer.new(io).write_frame(frame)
      io.rewind
      io
    end

    def read_frame(io)
      Protocol::HTTP2::Framer.new(io).read_frame
    end

    it "registers PRIORITY_UPDATE at our frame type (RFC 9218 7.1)" do
      expect(Protocol::HTTP2::FRAMES[Fast::Priority::H2::FRAME_TYPE]).to be(:==, Protocol::HTTP2::PriorityUpdateFrame)
    end

    it "builds the full frame exactly: header stream ID 0, type 0x10, payload after 9 bytes" do
      frame = Protocol::HTTP2::PriorityUpdateFrame.new(0)
      frame.pack(5, "u=1, i")
      wire = write_frame(frame).string
      expect(wire.unpack1("H*")).to be(:==, "00000a10000000000000000005753d312c2069")
      expect(wire.bytesize).to be(:==, 19)
    end

    it "decodes what their writer wrote (their frame through our codec)" do
      frame = Protocol::HTTP2::PriorityUpdateFrame.new(0)
      frame.pack(5, "u=1, i")
      decoded = Fast::Priority::H2.decode_payload(frame.payload)
      expect(decoded.stream_id).to be(:==, 5)
      expect(decoded.field_value).to be(:==, "u=1, i")
      expect(decoded.priority.urgency).to be(:==, 1)
      expect(decoded.priority.incremental).to be(:==, true)
      expect(decoded.error).to be(:nil?)
    end

    it "encodes exactly what their pack builds (our codec through their writer)" do
      priority = Fast::Priority.parse("u=1, i")
      theirs = Protocol::HTTP2::PriorityUpdateFrame.new(0)
      theirs.pack(5, priority.to_s)
      expect(Fast::Priority::H2.encode_payload(5, priority)).to be(:==, theirs.payload)
    end

    it "reads our payload through their framer (the full frame round trip)" do
      priority = Fast::Priority.parse("u=2, i, foo=bar")
      payload = Fast::Priority::H2.encode_payload(0x1234567, priority)
      frame = Protocol::HTTP2::PriorityUpdateFrame.new(
        0, 0, Protocol::HTTP2::PriorityUpdateFrame::TYPE, payload.bytesize, payload
      )
      received = read_frame(write_frame(frame))
      expect(received).to be(:kind_of?, Protocol::HTTP2::PriorityUpdateFrame)
      stream_id, field_value = received.unpack
      expect(stream_id).to be(:==, 0x1234567)
      expect(field_value).to be(:==, "u=2, i, foo=bar")
      decoded = Fast::Priority::H2.decode_payload(received.payload)
      expect(decoded.stream_id).to be(:==, stream_id)
      expect(decoded.field_value).to be(:==, field_value)
    end

    it "surfaces a malformed field value their stack handed us without raising" do
      frame = Protocol::HTTP2::PriorityUpdateFrame.new(0)
      frame.pack(7, "!!")
      decoded = Fast::Priority::H2.decode_payload(frame.payload)
      expect(decoded.stream_id).to be(:==, 7)
      expect(decoded.error).to be(:kind_of?, Fast::Priority::ParseError)
      expect(decoded.priority.urgency).to be(:==, 3)
    end
  end
end
