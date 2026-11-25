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

    # The value tree is not serializable as a Structured Field Value: the
    # strict RFC 9651 §4.1 emit could not proceed (a sender never puts
    # garbage on the wire — §1.2 demands behavior indistinguishable from
    # the algorithms, so there is no lenient reading to fall back to).
    # #offset is the byte position in the output built so far, an Integer
    # in 0..output.bytesize; #message carries the reason. The whole emit
    # path raises this class and never TypeError: on emit the wrongness
    # is in the value tree being sent — wrong types, wrong shapes,
    # out-of-range values, invalid key or string content — which is field
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
