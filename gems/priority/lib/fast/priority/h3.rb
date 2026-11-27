# frozen_string_literal: true

module Fast
  module Priority
    # RFC 9218 §7.2: the HTTP/3 PRIORITY_UPDATE frame payload codec.
    # REQUEST_TYPE (0xF0700, request streams) and PUSH_TYPE (0xF0701,
    # push streams) are the frame header's type field — the constants a
    # caller cites. The type is itself a QUIC variable-length integer
    # on the wire (0xF0700 = 984832, a 4-byte form, spelled 80 0f 07
    # 00), and it lives in the frame header, never in this payload.
    #
    # The payload is Figure 2's tail: the Prioritized Element ID — "The
    # stream ID or push ID that is the target of the priority update" —
    # as a QUIC variable-length integer (RFC 9000 §16), then the
    # Priority Field Value, "the priority update value in ASCII text
    # that uses the same representation as that of the Priority header
    # field value".
    #
    # The frame header and placement are the transport's: the type and
    # length varints, and the client control stream the frame MUST be
    # sent on (receiving it on another stream is a connection error of
    # type H3_FRAME_UNEXPECTED). The reference rules are the caller's
    # too, and they are connection policy this gem keeps no state for:
    # the request-stream variant (0xF0700) must reference a request
    # stream and the push-stream variant (0xF0701) a promised push
    # stream, a violation being a connection error of type H3_ID_ERROR
    # (§7.2).
    module H3
      # §7.2: "PRIORITY_UPDATE with a frame type of 0xF0700 is used
      # for request streams".
      REQUEST_TYPE = 0xF0700
      # §7.2: "PRIORITY_UPDATE with a frame type of 0xF0701 is used
      # for push streams".
      PUSH_TYPE = 0xF0701
      # RFC 9000 §16, Table 4: the 8-byte form's 62 usable bits —
      # the Prioritized Element ID's whole range.
      MAX_ELEMENT_ID = (1 << 62) - 1
      # The first byte's low 6 bits — the value bits every form
      # carries in its first byte (§16).
      VARINT_MASK = 0x3F

      # The decode result. #element_id is the Prioritized Element ID
      # (the stream ID or push ID that is the target); #field_value the
      # raw Priority Field Value, ASCII-8BIT — the payload's bytes
      # whatever tag the input String carried; #priority the §4
      # recipient parse of the field value; #error §7's signal for the
      # CALLER: "Failure to parse the Priority Field Value MAY be
      # treated as a connection error. In HTTP/3, the error is of type
      # H3_GENERAL_PROTOCOL_ERROR" — the wrapped RFC 9651 Dictionary
      # failure, nil when the value parsed. A parsed-but-ignored member
      # is not a failure (§4's MUST-ignore governs), so #priority is
      # the defaults only when #error is set. Frozen, like every family
      # result.
      class Frame
        attr_reader :element_id, :field_value, :priority, :error

        def initialize(element_id, field_value, priority, error)
          @element_id = element_id
          @field_value = field_value
          @priority = priority
          @error = error
          freeze
        end
      end

      module_function

      # The §7.2 payload as an ASCII-8BIT String: the Prioritized
      # Element ID as its minimal QUIC varint, then the Parameters'
      # canonical to_s. Strict, like every emit: a value that is not a
      # Parameters raises SerializeError, because no unvalidated value
      # reaches the wire, and so does an identifier beyond the 62-bit
      # range.
      def encode_payload(element_id, priority)
        check_priority(priority)
        check_element_id(element_id)
        (varint(element_id) << priority.to_s)
      end

      # The §7.2 payload decoded: the Prioritized Element ID in
      # whatever varint form it arrived, the raw field value, the §4
      # parse of it, and the §7 error. Never raises on field content;
      # TypeError for a non-String payload; an empty payload, or one
      # whose varint prefix promises more bytes than it carries,
      # raises ParseError at the payload's byte size — where the scan
      # stopped.
      def decode_payload(payload)
        check_payload(payload)
        raise ParseError.new("the payload carries a Prioritized Element ID varint", 0) if payload.empty?

        length = 1 << (payload.getbyte(0) >> 6)
        size = payload.bytesize
        if size < length
          raise ParseError.new("the varint prefix promises #{length} bytes and the payload carries #{size}", size)
        end

        element_id = varint_value(payload, length)
        field_value = payload.byteslice(length, size - length)
        field_value.force_encoding(Encoding::ASCII_8BIT)
        field = Field.new(field_value)
        Frame.new(element_id, field_value, field.parameters, field.error)
      end

      # RFC 9000 §16: the minimal form — the smallest of the four
      # lengths that holds the value, the length's 2-MSB prefix OR'd
      # into the first byte, the value in network byte order. ("Values
      # do not need to be encoded on the minimum number of bytes
      # necessary, with the sole exception of the Frame Type field" —
      # the Prioritized Element ID is not that field, but this encoder
      # still emits the minimum.)
      def varint(value)
        case value
        when 0..0x3F then [value].pack("C")
        when 0..0x3FFF then [value | 0x4000].pack("n")
        when 0..0x3FFF_FFFF then [value | 0x8000_0000].pack("N")
        else [value | 0xC000_0000_0000_0000].pack("Q>")
        end
      end

      # RFC 9000 Appendix A.1's ReadVarint fold: the first byte's low 6
      # bits, then each remaining byte of the +length+ the prefix
      # promised, in network byte order. ANY of the four forms decodes,
      # minimal or not — §16's sole must-be-minimal exception is the
      # Frame Type field, and the Prioritized Element ID is not one.
      def varint_value(payload, length)
        value = payload.getbyte(0) & VARINT_MASK
        index = 1
        while index < length
          value = (value << 8) | payload.getbyte(index)
          index += 1
        end
        value
      end

      # The emit path never raises TypeError: the wrongness is in the
      # value being sent.
      def check_priority(priority)
        case priority
        when Parameters
          nil
        else
          raise SerializeError.new("a Fast::Priority::Parameters is required (got #{shape(priority)})", 0)
        end
      end

      # §16 Table 4's whole range.
      def check_element_id(element_id)
        valid = case element_id
                when Integer then element_id.between?(0, MAX_ELEMENT_ID)
                else false
                end
        return if valid

        raise SerializeError.new("the prioritized element ID is an Integer 0..2^62-1 (got #{shape(element_id)})", 0)
      end

      # The class of a value an error message names, or a placeholder
      # when the value has none (a BasicObject descendant) — the
      # message never calls a method on the value it is rejecting.
      def shape(value)
        defined?(value.class) ? value.class : "a classless object"
      end

      # The payload is a binary String read bytewise; anything else is
      # a caller bug.
      def check_payload(payload)
        return if payload.is_a?(String)

        raise TypeError, "a binary payload String is required (got #{payload.class})"
      end

      private_class_method :check_priority, :check_element_id, :check_payload, :varint, :varint_value, :shape
    end
  end
end
