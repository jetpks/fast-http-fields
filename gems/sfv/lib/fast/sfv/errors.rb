# frozen_string_literal: true

module Fast
  module SFV
    # The family root: every Fast::SFV failure descends from Error, so a
    # caller can guard the whole surface with one rescue (BRIEF §3).
    class Error < StandardError; end

    # The field value is not a Structured Field Value at all: the strict
    # RFC 9651 §4.2 parse could not proceed (§1.1 forbids tolerance, so
    # there is no lenient reading to fall back to). #offset is the byte
    # position in the combined input where the parse stopped, an Integer
    # in 0..input.bytesize; #message carries the reason. A wrong input
    # type is a caller bug, not field content: it raises plain TypeError
    # and never this class.
    class ParseError < Error
      attr_reader :offset

      def initialize(message, offset)
        super(message)
        @offset = offset
      end
    end
  end
end
