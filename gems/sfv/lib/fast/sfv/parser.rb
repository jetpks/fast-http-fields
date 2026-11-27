# frozen_string_literal: true

module Fast
  module SFV
    # The RFC 9651 §4.2 parse path: one instance per parse, walking the
    # combined field value by byte index — first-byte dispatch into the
    # eight bare-item grammars, character-class tables for the
    # continuation sets, no pattern machinery anywhere. The six entry
    # points at the bottom of this file construct one Parser and read the
    # result off it.
    class Parser
      # Builds a 256-entry byte class: true for every byte of +spec+, so a
      # table lookup answers "is this byte in the class" in one step.
      def self.byte_class(spec)
        table = Array.new(256, false)
        spec.each_byte { |byte| table[byte] = true }
        table.freeze
      end

      # Builds a 256-entry byte-value table: the index of every byte of
      # +spec+, for the base64 decode walk (the alphabet was validated
      # before any lookup, so the zero filler is never read).
      def self.byte_values(spec)
        table = Array.new(256, 0)
        spec.each_byte.with_index { |byte, index| table[byte] = index }
        table.freeze
      end

      UPPER = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
      LOWER = "abcdefghijklmnopqrstuvwxyz"
      DIGITS = "0123456789"

      # A key's first byte: lcalpha or "*" (§4.2.3.3 step 1).
      KEY_FIRST = byte_class("#{LOWER}*")
      # A key's continuation: lcalpha, DIGIT, "_", "-", "." or "*" (§4.2.3.3).
      KEY_BODY = byte_class("#{LOWER}#{DIGITS}_-.*")
      # A token's first byte: ALPHA or "*" (§4.2.6 step 1).
      TOKEN_FIRST = byte_class("#{UPPER}#{LOWER}*")
      # A token's continuation: tchar (RFC 9110) plus ":" and "/", the two
      # bytes §4.2.6 adds to the HTTP token set.
      TOKEN_BODY = byte_class("#{UPPER}#{LOWER}#{DIGITS}!#$%&'*+-.^_`|~:/")
      # One DIGIT of an integer or decimal (§4.2.4).
      DIGIT = byte_class(DIGITS)
      # The base64 alphabet including its pad byte (§4.2.7 step 6).
      B64 = byte_class("#{UPPER}#{LOWER}#{DIGITS}+/=")
      # The base64 alphabet's decode values.
      B64_VALUE = byte_values("#{UPPER}#{LOWER}#{DIGITS}+/")
      # A display string percent-escape digit: 0-9 or a-f (§4.2.10).
      HEX = byte_class("#{DIGITS}abcdef")
      # The bytes that may follow an inner list item: SP or ")"
      # (§4.2.1.2 step 3.5).
      INNER_BOUNDARY = byte_class(" )")
      # The two bytes a string escape may carry: DQUOTE and backslash
      # (§4.2.5 step 4.3).
      STRING_ESCAPE = byte_class("\"\\")
      # Optional whitespace, SP or tab: the byte the List and Dictionary
      # separators discard (§4.2.1 step 2.2, §4.2.2 step 2.6).
      OWS = byte_class(" \t")

      SP = 0x20
      COMMA = 0x2C
      SEMICOLON = 0x3B
      COLON = 0x3A
      LPAREN = 0x28
      RPAREN = 0x29
      DQUOTE = 0x22
      BACKSLASH = 0x5C
      HYPHEN = 0x2D
      PERIOD = 0x2E
      EQUALS = 0x3D
      PERCENT = 0x25
      QUESTION = 0x3F
      AT_SIGN = 0x40

      # Items and inner lists without parameters share this one Hash —
      # nothing can mutate a frozen Hash, so every #params is frozen and
      # empty either way, and a bare item costs no parameter allocation.
      EMPTY_PARAMS = {}.freeze
      # The byte sequence "::" — shared for the same reason.
      EMPTY_BYTES = "".b.freeze

      # The input is one String field value, or the field's lines as an
      # Array, combined with ", " (§4.2's combining rule — a Rack join
      # conforms; the one FieldValue implementation, shared with the
      # region scan). Anything else is a caller bug: TypeError, not a
      # Fast::SFV::Error.
      def initialize(input)
        @input = FieldValue.of(input)
        @pos = 0
        @end = @input.bytesize
      end

      # §4.2 steps 1-8 with field_type "item": one Item, or a ParseError.
      def item
        check_ascii
        skip_sp
        member = item_member
        skip_sp
        check_end
        member
      end

      # §4.2 steps 1-8 with field_type "list": a frozen Array of Items and
      # InnerLists. Empty input is the empty list (§4.2.1 step 3).
      def list
        check_ascii
        skip_sp
        members = list_members
        skip_sp
        check_end
        members.freeze
      end

      # §4.2 steps 1-8 with field_type "dictionary": a frozen, ordered
      # Hash of String keys to Items and InnerLists. Empty input is the
      # empty dictionary (§4.2.2 step 3).
      def dictionary
        check_ascii
        skip_sp
        members = dictionary_members
        skip_sp
        check_end
        members.freeze
      end

      private

      # §4.2 step 1: the whole field value must be ASCII — a byte above
      # 0x7F fails the parse before any grammar runs. ascii_only? is the
      # one-scan hot path; the walk runs only on failure, to find the
      # offset the error reports. The walk is bounded at @end: a
      # non-ASCII-compatible encoding can spell a byte string whose every
      # byte is ASCII-range (UTF-16LE "1" is "1\x00"), and getbyte past
      # the end answers nil — so a walk that completes with no offending
      # byte simply returns, and the grammar rejects the value positioned
      # (the padding NUL is in no grammar class).
      def check_ascii
        return if @input.ascii_only?

        index = 0
        index += 1 while index < @end && @input.getbyte(index) <= 0x7F
        return if index >= @end

        @pos = index
        fail_parse("the field value must be ASCII")
      end

      # §4.2 steps 6 and 7: trailing SP is fine, anything else fails.
      def check_end
        fail_parse("unexpected content after the value") unless @pos >= @end
      end

      # Discards leading SP (§4.2 steps 2 and 6, the *SP of §4.2.3.2 and
      # the 1*SP of §4.2.1.2).
      def skip_sp
        @pos += 1 while @pos < @end && @input.getbyte(@pos) == SP
      end

      # Discards leading OWS, SP or tab, around the list and dictionary
      # commas.
      def skip_ows
        @pos += 1 while @pos < @end && OWS[@input.getbyte(@pos)]
      end

      # The byte at @pos, NUL when the input is exhausted: NUL is in no
      # grammar class, so every table lookup and delimiter comparison
      # fails cleanly at end of input instead of raising.
      def byte
        @pos < @end ? @input.getbyte(@pos) : 0
      end

      # §4.2.1 Parsing a List: members separated by OWS "," OWS; a trailing
      # comma fails (step 2.6), and a member that cannot parse fails the
      # whole list, so an empty member never slips through.
      def list_members
        members = []
        while @pos < @end
          members << item_or_inner_list
          skip_ows
          return members if @pos >= @end

          separator = @input.getbyte(@pos)
          @pos += 1
          fail_parse("list members are separated by ','") unless separator == COMMA
          skip_ows
          fail_parse("a list may not end with ','") if @pos >= @end
        end
        members
      end

      # §4.2.2 Parsing a Dictionary: key, then "=" and a member, or the
      # valueless short form (Boolean true with parameters); members
      # separated by OWS "," OWS; a trailing comma fails. A duplicate key
      # overwrites the value at its first position — exactly what a Ruby
      # Hash assignment does.
      def dictionary_members
        dictionary = {}
        while @pos < @end
          key = parse_key
          if byte == EQUALS
            @pos += 1
            dictionary[key] = item_or_inner_list
          else
            dictionary[key] = Item.new(true, parse_parameters)
          end
          skip_ows
          return dictionary if @pos >= @end

          separator = @input.getbyte(@pos)
          @pos += 1
          fail_parse("dictionary members are separated by ','") unless separator == COMMA
          skip_ows
          fail_parse("a dictionary may not end with ','") if @pos >= @end
        end
        dictionary
      end

      # §4.2.1.1: "(" opens an inner list; anything else is a single item.
      def item_or_inner_list
        if byte == LPAREN
          inner_list
        else
          item_member
        end
      end

      # §4.2.1.2 Parsing an Inner List: items separated by 1*SP only, so a
      # tab inside fails; after every item the next byte must be SP or ")";
      # ")" closes the list and carries its parameters. The dispatch has
      # already checked the "(".
      def inner_list
        @pos += 1
        items = []
        while @pos < @end
          skip_sp
          if byte == RPAREN
            @pos += 1
            return InnerList.new(items.freeze, parse_parameters)
          end

          items << item_member
          boundary = byte
          fail_parse("an inner list item must be followed by SP or ')'") unless INNER_BOUNDARY[boundary]
        end
        fail_parse("an inner list must be closed with ')'")
      end

      # §4.2.3 Parsing an Item: a bare item, then its parameters.
      def item_member
        Item.new(parse_bare_item, parse_parameters)
      end

      # §4.2.3.1 Parsing a Bare Item: dispatch on the first byte, in the
      # RFC's own order. An exhausted input lands on NUL, which is in no
      # class, so an empty item fails here.
      def parse_bare_item
        first = byte
        if first == HYPHEN || DIGIT[first]
          parse_number
        elsif first == DQUOTE
          parse_string
        elsif TOKEN_FIRST[first]
          parse_token
        elsif first == COLON
          parse_byte_sequence
        elsif first == QUESTION
          parse_boolean
        elsif first == AT_SIGN
          parse_date
        elsif first == PERCENT
          parse_display_string
        else
          fail_parse("an item must start with a bare item byte")
        end
      end

      # §4.2.3.2 Parsing Parameters: ";" then *SP then a key, then "=" and
      # a bare item, or the valueless form Boolean true. A duplicate key
      # overwrites the value at its first position; items with no
      # parameters share the one frozen empty Hash.
      def parse_parameters
        params = nil
        while byte == SEMICOLON
          @pos += 1
          skip_sp
          key = parse_key
          value = true
          if byte == EQUALS
            @pos += 1
            value = parse_bare_item
          end
          (params ||= {})[key] = value
        end
        (params || EMPTY_PARAMS).freeze
      end

      # §4.2.3.3 Parsing a Key: lcalpha or "*" first, then lcalpha, DIGIT,
      # "_", "-", "." or "*". The first advance is covered by the
      # KEY_FIRST check.
      def parse_key
        fail_parse("a key must start with a lowercase letter or '*'") unless KEY_FIRST[byte]

        start = @pos
        @pos += 1
        @pos += 1 while KEY_BODY[byte]
        @input.byteslice(start, @pos - start).force_encoding(Encoding::UTF_8).freeze
      end

      # §4.2.4 Parsing an Integer or Decimal: an optional "-", then DIGITs
      # with at most one "." — 12 integer digits and 3 fraction digits when
      # decimal, 15 digits when integer, 16 characters in all. The scan
      # walks the digits; #number_magnitude applies the limits and converts.
      def parse_number
        negative = byte == HYPHEN
        @pos += 1 if negative
        fail_parse("a number must start with a digit") unless DIGIT[byte]

        start = @pos
        period = nil
        while @pos < @end
          current = @input.getbyte(@pos)
          if DIGIT[current]
            @pos += 1
          elsif period.nil? && current == PERIOD
            fail_parse("a decimal carries at most 12 integer digits") if @pos - start > 12

            period = @pos
            @pos += 1
          else
            break
          end
        end

        magnitude = number_magnitude(start, period)
        negative ? -magnitude : magnitude
      end

      # The magnitude the scanned digits spell, limits applied: a Float
      # when a period was walked (to_f on the whole literal), the
      # in-place Integer otherwise.
      def number_magnitude(start, period)
        if period
          fail_parse("a decimal is at most 16 characters") if @pos - start > 16
          fail_parse("a decimal must end with a fraction digit") if @pos - period == 1
          fail_parse("a decimal carries at most 3 fraction digits") if @pos - period > 4

          @input.byteslice(start, @pos - start).to_f
        else
          fail_parse("an integer is at most 15 digits") if @pos - start > 15

          integer_from(start)
        end
      end

      # The integer the DIGIT bytes from +start+ to @pos spell, accumulated
      # in place: no intermediate String, and a 15-digit value stays inside
      # the immediate Integers.
      def integer_from(start)
        value = 0
        while start < @pos
          value = value * 10 + (@input.getbyte(start) - 0x30)
          start += 1
        end
        value
      end

      # §4.2.5 Parsing a String: DQUOTE-delimited; a backslash escapes only
      # DQUOTE and backslash; every other byte must be SP or VCHAR. The
      # content is one contiguous byte range until the first escape, so the
      # common case is a single slice; from the first escape on, every
      # later byte joins the buffer.
      def parse_string
        @pos += 1
        start = @pos
        content = nil
        while @pos < @end
          current = @input.getbyte(@pos)
          if current == BACKSLASH
            content ||= @input.byteslice(start, @pos - start)
            @pos += 1
            fail_parse("a string escape must be followed by a character") if @pos >= @end

            escaped = @input.getbyte(@pos)
            fail_parse("only '\"' and '\\' may be escaped in a string") unless STRING_ESCAPE[escaped]

            content << escaped
            @pos += 1
          elsif current == DQUOTE
            text = content || @input.byteslice(start, @pos - start)
            @pos += 1
            return text.force_encoding(Encoding::UTF_8).freeze
          elsif current < SP || current > 0x7E
            fail_parse("a string may only carry SP and printable ASCII")
          else
            content << current if content
            @pos += 1
          end
        end
        fail_parse("a string must be closed with '\"'")
      end

      # §4.2.6 Parsing a Token: ALPHA or "*" first, then tchar, ":" or "/" —
      # a Token on the Ruby side: the class is the wire-type tag, and the
      # constructor re-validates the walked bytes at the boundary.
      def parse_token
        start = @pos
        @pos += 1
        @pos += 1 while TOKEN_BODY[byte]
        Token.new(@input.byteslice(start, @pos - start))
      end

      # §4.2.7 Parsing a Byte Sequence: ":" ... ":" over the base64
      # alphabet, "=" only as the trailing pad. The decode synthesizes
      # padding, so unpadded, over-padded and dirty-padded values all
      # decode; a character outside the alphabet, a misplaced pad or a
      # lone trailing character fails.
      def parse_byte_sequence
        @pos += 1
        start = @pos
        close = start
        close += 1 while close < @end && @input.getbyte(close) != COLON
        fail_parse("a byte sequence must be closed with ':'") if close >= @end

        # The data characters run to the first "=", and everything after it
        # must be that trailing "=" run and nothing else.
        data_end = start
        data_end += 1 while data_end < close && @input.getbyte(data_end) != EQUALS
        validate_base64(start, data_end, close)

        @pos = close + 1
        decode_bytes(start, data_end)
      end

      # The characters in start...data_end must be base64, the rest of
      # the run up to +close+ the trailing "=" pad and nothing else.
      def validate_base64(start, data_end, close)
        index = start
        while index < data_end
          fail_parse("a byte sequence may only carry base64 characters") unless B64[@input.getbyte(index)]

          index += 1
        end
        while index < close
          fail_parse("base64 '=' may only pad the end of the content") unless @input.getbyte(index) == EQUALS

          index += 1
        end
      end

      # §4.2.7 step 7: the base64 decode of the data characters with the
      # padding synthesized — four characters to three bytes, a trailing
      # pair to one, a trailing triple to two.
      def decode_bytes(start, data_end)
        length = data_end - start
        return EMPTY_BYTES if length.zero?

        bytes = "".b
        index = start
        remaining = length
        while remaining >= 4
          value = group_value(index, 4)
          bytes << (value >> 16) << ((value >> 8) & 0xFF) << (value & 0xFF)
          index += 4
          remaining -= 4
        end

        case remaining
        when 2
          bytes << (group_value(index, 2) >> 16)
        when 3
          value = group_value(index, 3)
          bytes << (value >> 16) << ((value >> 8) & 0xFF)
        when 1
          fail_parse("a byte sequence may not end with a single base64 character")
        end
        bytes.freeze
      end

      # The 24-bit value of the +count+ base64 characters at +index+ —
      # four characters, or the trailing pair or triple with the
      # missing low places zero.
      def group_value(index, count)
        value = B64_VALUE[@input.getbyte(index)] << 18
        value |= B64_VALUE[@input.getbyte(index + 1)] << 12 if count > 1
        value |= B64_VALUE[@input.getbyte(index + 2)] << 6 if count > 2
        value |= B64_VALUE[@input.getbyte(index + 3)] if count > 3
        value
      end

      # §4.2.8 Parsing a Boolean: exactly "?1" or "?0". The dispatch has
      # already consumed the "?".
      def parse_boolean
        @pos += 1
        fail_parse("a boolean is '?' followed by '1' or '0'") if @pos >= @end

        value = @input.getbyte(@pos)
        @pos += 1
        return true if value == 0x31
        return false if value == 0x30

        fail_parse("a boolean is '?' followed by '1' or '0'")
      end

      # §4.2.9 Parsing a Date: "@" then an Integer — a Decimal fails. The
      # dispatch has already consumed the "@".
      def parse_date
        @pos += 1
        value = parse_number
        fail_parse("a date is '@' followed by an integer, not a decimal") if value.is_a?(Float)

        Date.new(value)
      end

      # §4.2.10 Parsing a Display String: `%"` ... `"`, literal bytes SP or
      # VCHAR, "%" always exactly two lowercase hex digits; the collected
      # bytes must decode as UTF-8 at the closing quote. The dispatch has
      # already consumed the "%".
      def parse_display_string
        @pos += 1
        fail_parse("a display string must open with '%\"'") unless byte == DQUOTE

        @pos += 1
        bytes = display_string_bytes
        text = bytes.force_encoding(Encoding::UTF_8)
        fail_parse("a display string must be valid UTF-8") unless text.valid_encoding?

        DisplayString.new(text.freeze)
      end

      # The raw bytes between the quotes, percent-escapes decoded — the
      # closing DQUOTE consumed; every other failure raises on the walk.
      def display_string_bytes
        bytes = "".b
        while @pos < @end
          current = @input.getbyte(@pos)
          fail_parse("a display string may only carry SP and printable ASCII") if current < SP || current > 0x7E

          if current == PERCENT
            @pos += 1
            fail_parse("a display string escape needs two hex digits") if @pos + 1 >= @end

            high = @input.getbyte(@pos)
            low = @input.getbyte(@pos + 1)
            fail_parse("a display string escape needs lowercase hex digits") unless HEX[high] && HEX[low]

            bytes << (hex_value(high) * 16 + hex_value(low))
            @pos += 2
          elsif current == DQUOTE
            @pos += 1
            return bytes
          else
            bytes << current
            @pos += 1
          end
        end
        fail_parse("a display string must be closed with '\"'")
      end

      # The value of one lowercase hex digit, already validated by HEX.
      def hex_value(byte)
        byte <= 0x39 ? byte - 0x30 : byte - 0x61 + 10
      end

      # Raises the positioned ParseError: the reason, and the byte offset
      # into the combined input where the parse stopped.
      def fail_parse(reason)
        raise ParseError.new("#{reason} at offset #{@pos}", @pos)
      end
    end

    private_constant :Parser

    module_function

    # Parses one RFC 9651 Item (§4.2, field_type "item") — a bare item
    # with parameters, as a frozen Fast::SFV::Item.
    #
    # Strict: malformed field content raises ParseError; a non-String,
    # non-Array input raises TypeError.
    def parse_item(input)
      Parser.new(input).item
    end

    # Parses an RFC 9651 List (§4.2, field_type "list") — a frozen Array
    # of Items and InnerLists. Empty input parses to the empty list.
    #
    # Strict: malformed field content raises ParseError; a non-String,
    # non-Array input raises TypeError.
    def parse_list(input)
      Parser.new(input).list
    end

    # Parses an RFC 9651 Dictionary (§4.2, field_type "dictionary") — a
    # frozen, ordered Hash of String keys to Items and InnerLists. Empty
    # input parses to the empty dictionary.
    #
    # Strict: malformed field content raises ParseError; a non-String,
    # non-Array input raises TypeError.
    def parse_dict(input)
      Parser.new(input).dictionary
    end

    # The total predicate mirrors: the strict parse with a boolean answer
    # that never raises — false for malformed content and for a wrong
    # input type alike (a caller bug is not field content either).
    def valid_item?(input)
      parse_item(input)
      true
    rescue TypeError, ParseError
      false
    end

    # See valid_item?.
    def valid_list?(input)
      parse_list(input)
      true
    rescue TypeError, ParseError
      false
    end

    # See valid_item?.
    def valid_dict?(input)
      parse_dict(input)
      true
    rescue TypeError, ParseError
      false
    end
  end
end
