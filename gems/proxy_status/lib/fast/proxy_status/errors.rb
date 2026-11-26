# frozen_string_literal: true

module Fast
  class ProxyStatus
    # The family root: every Fast::ProxyStatus failure descends from
    # Error, so a caller can guard the whole surface with one rescue.
    # This class is never raised in its own right — every failure here
    # is either a parse defect or a serialization defect — but the
    # family shape keeps the base so one rescue guards them all. A
    # wrong input type is a caller bug, not field content: it raises
    # plain TypeError and never this class.
    class Error < StandardError; end

    # A Proxy-Status field this gem cannot read. Two shapes meet here:
    # the underlying RFC 9651 List failed to parse — the failure is
    # wrapped with its message and byte offset preserved — or, under the
    # strict parse, a member broke RFC 9209 §2's constraint (a member
    # that is not a String or Token) or a §2.1 parameter broke its
    # section's type, and #offset is the byte position of the offending
    # member's identifier or parameter VALUE in the combined field value
    # (a member's, the member's first non-OWS byte; a parameter's, just
    # past the "=" — the key's end for the valueless form, the implicit
    # Boolean true). The lenient parse never raises it: a recipient that
    # cannot read the field ignores it entirely (RFC 9651 §2.2).
    class ParseError < Error
      attr_reader :offset

      def initialize(message, offset)
        super(message)
        @offset = offset
      end
    end

    # A value cannot go on the wire: the field under construction breaks
    # a bound RFC 9209 states — a member identifier that is not a plain
    # String or a Fast::SFV::Token (a String tagged ASCII-8BIT would
    # emit as a Byte Sequence), a §2.1 parameter of a type its section
    # does not allow, an unknown parameter of a non-bare type, a
    # parameter key outside the Structured Fields key grammar, or
    # members that are not Hops. #offset is the byte position in the
    # output built so far — 0, because the check runs before anything is
    # emitted; the whole emit path raises this class and never TypeError:
    # on emit the wrongness is in the value being sent, which is field
    # content, not a caller protocol bug.
    class SerializeError < Error
      attr_reader :offset

      def initialize(message, offset)
        super(message)
        @offset = offset
      end
    end
  end
end
