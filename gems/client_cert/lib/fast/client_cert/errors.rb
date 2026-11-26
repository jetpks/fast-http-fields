# frozen_string_literal: true

module Fast
  module ClientCert
    # The family root: every Fast::ClientCert failure descends from
    # Error, so a caller can guard the whole surface with one rescue.
    # Error is also raised in its own right, by the PEM helpers: an
    # armor-shape failure (no BEGIN line, the END missing, no payload,
    # a second block) or a field value that is not a whole base64 item
    # is a USAGE failure — neither a parse defect (the field never
    # parsed) nor a serialization defect (nothing was built) — so it
    # answers the base class, and the message names the reason. A
    # wrong input type is a caller bug, not field content: it raises
    # plain TypeError and never this class.
    class Error < StandardError; end

    # A field this gem cannot read. Two shapes meet here: the
    # underlying RFC 9651 parse failed — the failure is wrapped with
    # its message and byte offset preserved — or, under the strict
    # parse, a value broke the field's RFC 9440 constraint (§2.2's
    # Byte Sequence Item, §2.3's Byte Sequence members), and #offset is
    # the byte position of the offending value in the combined field
    # value — for a chain, the first offender's first non-OWS byte.
    # The lenient parse never raises it: a recipient that cannot read
    # the field treats it as absent (RFC 9651 §2.2).
    class ParseError < Error
      attr_reader :offset

      def initialize(message, offset)
        super(message)
        @offset = offset
      end
    end

    # A value cannot go on the wire: the field under construction
    # breaks a bound RFC 9440 states — a DER that is not a String
    # tagged ASCII-8BIT and not a Token (a UTF-8 String would emit as
    # a quoted sf-string, a Token as a token — neither is the Byte
    # Sequence §2.1 demands), or a chain members argument that is not
    # an Array of them. #offset is the byte position in the output
    # built so far — 0, because the check runs before anything is
    # emitted; the whole emit path raises this class and never
    # TypeError: on emit the wrongness is in the value being sent,
    # which is field content, not a caller protocol bug.
    class SerializeError < Error
      attr_reader :offset

      def initialize(message, offset)
        super(message)
        @offset = offset
      end
    end
  end
end
