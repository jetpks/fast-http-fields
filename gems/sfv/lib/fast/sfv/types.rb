# frozen_string_literal: true

module Fast
  module SFV
    # A parsed Item (RFC 9651 §3.3): one bare item plus its parameters.
    # #value is one of the eight bare types — Integer, Float, a frozen
    # UTF-8 String, a Token, a frozen ASCII-8BIT String, true, false, a
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

      # The canonical wire form (RFC 9651 §4.1.3) — exactly what
      # Fast::SFV.serialize_item answers: the bare item, then its
      # parameters. Strict: a hand-built non-serializable value raises
      # SerializeError; a parse result never does, since every corpus
      # value round-trips. Computed on demand, so construction stays
      # as cheap as the parse path's frozen budgets require.
      def to_s
        Serializer.item_string(self)
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

      # The canonical wire form (RFC 9651 §4.1.1.1) — "(" and ")" around
      # the items joined by single SPs, the list's own parameters after
      # the close; "()" for the empty list. The same strictness as
      # Item#to_s.
      def to_s
        Serializer.inner_list_string(self)
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

      # The canonical wire form (RFC 9651 §4.1.10): "@" + the integer.
      def to_s
        Serializer.date_string(self)
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

      # The canonical wire form (RFC 9651 §4.1.11): `"` delimited, "%",
      # DQUOTE and the control/high bytes as "%" + two lowercase hex
      # digits, the ASCII bytes literal.
      def to_s
        Serializer.display_string_string(self)
      end
    end

    # A Token (RFC 9651 §3.3.4): a frozen String subclass whose class is
    # the wire-type tag. The content is String semantics, inherited
    # untouched — #==, #eql?, #hash and #to_s behave exactly as a plain
    # String's, so a Token compares equal to the String that spells it
    # in both directions and serves as a Hash key by content — while
    # Token-ness is what the parse and emit paths dispatch on: a quoted
    # sf-string is a plain String, a token is a Token, and the content
    # never decides which. Construction is the boundary: the content
    # must spell a whole token — ALPHA or "*" first, then tchar, ":" or
    # "/" (§4.2.6's own byte classes) — or ArgumentError; a non-String
    # raises TypeError, Ruby's own conversion error. No length cap
    # (§3.3.4 requires at least 512 characters) and no intern cache: a
    # repeated value builds its own Token, measured as one object beside
    # the content slice it is built from.
    class Token < String
      # Validates the token grammar on the content bytes — the parse
      # path's own classes, read lazily because types.rb loads before
      # parser.rb — then freezes: the only Token is a whole, valid,
      # immutable one.
      def initialize(content)
        super(content)
        size = bytesize
        raise ArgumentError, "a token must not be empty" if size.zero?
        unless Parser::TOKEN_FIRST[getbyte(0)]
          raise ArgumentError, "a token must start with ALPHA or '*' (got #{inspect})"
        end

        index = 1
        while index < size
          unless Parser::TOKEN_BODY[getbyte(index)]
            raise ArgumentError, "a token may only carry tchar, ':' and '/' (got #{inspect})"
          end

          index += 1
        end
        freeze
      end

      # The default String-subclass form is indistinguishable from a
      # plain String's inspect: the class name and the content together
      # say what the value is.
      def inspect
        "#<#{self.class.name} #{super}>"
      end
    end
  end
end
