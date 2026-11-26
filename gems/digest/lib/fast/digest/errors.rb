# frozen_string_literal: true

module Fast
  module Digest
    # The family root: every Fast::Digest failure descends from Error,
    # so a caller can guard the whole surface with one rescue. Error is
    # also raised in its own right, by the compute helpers
    # (Fast::Digest.compute and the two .of constructors): a checksum
    # algorithm the gem does not compute locally, or a key that is not
    # in the RFC 9530 hash algorithm registry, is a USAGE failure —
    # neither a parse defect (the field never parsed) nor a
    # serialization defect (nothing was built) — so it answers the base
    # class, and the message names the key and the reason. A wrong input
    # type is a caller bug, not field content: it raises plain TypeError
    # and never this class.
    class Error < StandardError; end

    # A Digest field this gem cannot read. Two shapes meet here: the
    # underlying RFC 9651 Dictionary failed to parse — the failure is
    # wrapped with its message and byte offset preserved — or, under the
    # strict parse, a member broke the field's RFC 9530 constraint (an
    # Integrity member that is not a Byte Sequence, a preference member
    # that is not an Integer 0..10), and #offset is the byte position of
    # that member's VALUE in the combined field value — the last
    # occurrence of the key, the member Fast::SFV's last-wins kept. The
    # lenient parse never raises it: a recipient that cannot read the
    # field ignores it entirely (RFC 9651 §2.2).
    class ParseError < Error
      attr_reader :offset

      def initialize(message, offset)
        super(message)
        @offset = offset
      end
    end

    # A value cannot go on the wire: the field under construction breaks
    # a bound RFC 9530 states — a member key that is not a Structured
    # Fields key (§1.4's Algorithm Keys are lowercase Dictionary keys),
    # an Integrity value that is not a String tagged ASCII-8BIT (it
    # would emit as a quoted sf-string, not a Byte Sequence), or a
    # preference value that is not an Integer 0..10 (§4). #offset is the
    # byte position in the output built so far — 0, because the check
    # runs before anything is emitted; the whole emit path raises this
    # class and never TypeError: on emit the wrongness is in the value
    # being sent, which is field content, not a caller protocol bug.
    class SerializeError < Error
      attr_reader :offset

      def initialize(message, offset)
        super(message)
        @offset = offset
      end
    end
  end
end
