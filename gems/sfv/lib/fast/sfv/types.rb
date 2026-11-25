# frozen_string_literal: true

module Fast
  module SFV
    # A parsed Item (RFC 9651 §3.3): one bare item plus its parameters.
    # #value is one of the eight bare types — Integer, Float, a frozen
    # UTF-8 String, a Symbol, a frozen ASCII-8BIT String, true, false, a
    # Date or a DisplayString; #params is the ordered, frozen, String-keyed
    # Hash the parser filled (empty and shared when there were none). The
    # instance is frozen at construction: nothing reachable from a parse
    # result can be mutated.
    class Item
      attr_reader :value, :params

      def initialize(value, params)
        @value = value
        @params = params
        freeze
      end
    end

    # A parsed Inner List (RFC 9651 §3.1.1): a frozen Array of Items plus
    # the parameters that belong to the list itself — the member Items
    # carry their own.
    class InnerList
      attr_reader :items, :params

      def initialize(items, params)
        @items = items
        @params = params
        freeze
      end
    end

    # A parsed Date (RFC 9651 §3.3.7): the Integer delta-seconds from
    # 1970-01-01T00:00:00Z, which rides in #value — Integer cannot be
    # subclassed, so the wrapper is the type tag.
    class Date
      attr_reader :value

      def initialize(value)
        @value = value
        freeze
      end
    end

    # A parsed Display String (RFC 9651 §3.3.8): a frozen UTF-8 String that
    # may carry non-ASCII content, percent-decoded by the parser.
    class DisplayString
      attr_reader :value

      def initialize(value)
        @value = value
        freeze
      end
    end
  end
end
