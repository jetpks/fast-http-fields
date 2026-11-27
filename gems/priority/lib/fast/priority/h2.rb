# frozen_string_literal: true

module Fast
  module Priority
    # RFC 9218 §7.1: the HTTP/2 PRIORITY_UPDATE frame payload codec.
    # FRAME_TYPE is 0x10, the frame header's type byte — the constant a
    # caller (or an interop peer's frame registry) cites.
    #
    # The payload is Figure 1's tail: the Reserved(1)+Prioritized
    # Stream ID(31) as one big-endian 32-bit word — the Reserved bit
    # written 0 on send and masked off on receipt, leaving §7.1's
    # "A 31-bit stream identifier for the stream that is the target of
    # the priority update" — then the Priority Field Value, "the
    # priority update value in ASCII text, ... the same representation
    # as the Priority header field value".
    #
    # The frame header is the transport's: the 9-byte Length, Type,
    # Unused Flags, and the header Stream Identifier §7.1 says MUST be
    # zero. The stream-state rules are the caller's too, and they are
    # connection policy this gem keeps no state for: a prioritized
    # stream ID of 0x0 is a connection error of type PROTOCOL_ERROR;
    # the open, half-closed (local) or idle expectations for request
    # streams, the reserved (remote) or half-closed (local) ones for
    # push streams, and the servers-MUST-NOT-send rule are all §7.1.
    # The SETTINGS_NO_RFC7540_PRIORITIES setting (§2.1, 0x9) is the h2
    # peer's way to disable RFC 7540 priority signals: sent in the
    # first SETTINGS frame, value 0 or 1, unchanged after; a client
    # value of 1 means the client ignores h2 priority signals, a
    # server value that the server will. A SETTINGS frame belongs to
    # the connection, so it is documentation here, never behavior.
    module H2
      # §7.1: "The HTTP/2 PRIORITY_UPDATE frame (type=0x10)".
      FRAME_TYPE = 0x10
      # §7.1: "Prioritized Stream ID: A 31-bit stream identifier" —
      # the field's bound, and the mask that strips Figure 1's Reserved
      # bit off the received word.
      MAX_STREAM_ID = 0x7FFF_FFFF
      # The payload's fixed prefix: the 4-byte Reserved+ID word.
      PREFIX_SIZE = 4

      # The decode result. #stream_id is the 31-bit prioritized stream
      # identifier (the Reserved bit masked off); #field_value the raw
      # Priority Field Value, ASCII-8BIT — the payload's bytes whatever
      # tag the input String carried; #priority the §4 recipient parse
      # of the field value; #error §7's signal for the CALLER: "Failure
      # to parse the Priority Field Value MAY be treated as a
      # connection error. In HTTP/2, the error is of type
      # PROTOCOL_ERROR" — the wrapped RFC 9651 Dictionary failure, nil
      # when the value parsed. A parsed-but-ignored member is not a
      # failure (§4's MUST-ignore governs), so #priority is the
      # defaults only when #error is set. Frozen, like every family
      # result.
      class Frame
        attr_reader :stream_id, :field_value, :priority, :error

        def initialize(stream_id, field_value, priority, error)
          @stream_id = stream_id
          @field_value = field_value
          @priority = priority
          @error = error
          freeze
        end
      end

      module_function

      # The §7.1 payload as an ASCII-8BIT String: the 4-byte word —
      # Reserved bit 0 — then the Parameters' canonical to_s. Strict,
      # like every emit: a value that is not a Parameters (a bare
      # String, say) raises SerializeError, because no unvalidated
      # value reaches the wire, and so does an identifier outside the
      # 31-bit field.
      def encode_payload(stream_id, priority)
        check_priority(priority)
        check_stream_id(stream_id)
        ([stream_id].pack("N") << priority.to_s)
      end

      # The §7.1 payload decoded: the 31-bit stream identifier with the
      # Reserved bit masked off, the raw field value, the §4 parse of
      # it, and the §7 error. Never raises on field content; TypeError
      # for a non-String payload; a payload shorter than the 4-byte
      # word raises ParseError at the payload's byte size — where the
      # scan stopped.
      def decode_payload(payload)
        check_payload(payload)
        size = payload.bytesize
        raise ParseError.new("the payload carries a 4-byte prioritized stream ID word", size) if size < PREFIX_SIZE

        stream_id = payload.unpack1("N") & MAX_STREAM_ID
        field_value = payload.byteslice(PREFIX_SIZE, size - PREFIX_SIZE)
        field_value.force_encoding(Encoding::ASCII_8BIT)
        field = Field.new(field_value)
        Frame.new(stream_id, field_value, field.parameters, field.error)
      end

      # The emit path never raises TypeError: the wrongness is in the
      # value being sent.
      def check_priority(priority)
        return if priority.is_a?(Parameters)

        raise SerializeError.new("a Fast::Priority::Parameters is required (got #{priority.class})", 0)
      end

      # §7.1's field bound, sender side: a prioritized stream ID of
      # 0x0 is the one identifier the RFC rejects unconditionally —
      # "If a PRIORITY_UPDATE frame is received with a prioritized
      # stream ID of 0x0, the recipient MUST respond with a connection
      # error of type PROTOCOL_ERROR" — so a strict sender never emits
      # one; the bound is 1..0x7FFFFFFF.
      def check_stream_id(stream_id)
        return if stream_id.is_a?(Integer) && stream_id.between?(1, MAX_STREAM_ID)

        raise SerializeError.new(
          "the prioritized stream ID is an Integer 1..0x7FFFFFFF, never 0 (got #{stream_id.inspect})", 0
        )
      end

      # The payload is a binary String read bytewise; anything else is
      # a caller bug.
      def check_payload(payload)
        return if payload.is_a?(String)

        raise TypeError, "a binary payload String is required (got #{payload.class})"
      end

      private_class_method :check_priority, :check_stream_id, :check_payload
    end
  end
end
