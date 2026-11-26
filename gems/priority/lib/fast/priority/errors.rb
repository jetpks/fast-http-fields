# frozen_string_literal: true

module Fast
  module Priority
    # The family root: every Fast::Priority failure descends from
    # Error, so a caller can guard the whole surface with one rescue.
    class Error < StandardError; end

    # A priority signal this gem cannot read. Two shapes meet here:
    # the underlying RFC 9651 Dictionary failed to parse — the failure
    # is wrapped with its message and byte offset preserved — or, under
    # the strict parse, a member broke a RFC 9218 §4 parameter rule
    # ("u" not an Integer 0..7, "i" not a Boolean), and #offset is the
    # byte position of that member's VALUE in the combined field value.
    # The frame payload codecs use the same class for payloads too
    # short to carry their fixed prefix. A wrong input type is a caller
    # bug, not field content: it raises plain TypeError and never this
    # class. The lenient parse never raises it — §4's recipients are
    # told to ignore what they cannot read.
    class ParseError < Error
      attr_reader :offset

      def initialize(message, offset)
        super(message)
        @offset = offset
      end
    end

    # A value cannot go on the wire: the Parameters under construction,
    # or the stream or element identifier handed to a frame encoder,
    # breaks a bound the RFC states (§4.1's Integer 0..7, §4.2's
    # Boolean, §7.1's 31-bit stream identifier, §7.2's 62-bit element
    # identifier). #offset is the byte position in the output built so
    # far — 0, because the check runs before anything is emitted; the
    # whole emit path raises this class and never TypeError: on emit
    # the wrongness is in the value being sent, which is field content,
    # not a caller protocol bug.
    class SerializeError < Error
      attr_reader :offset

      def initialize(message, offset)
        super(message)
        @offset = offset
      end
    end
  end
end
