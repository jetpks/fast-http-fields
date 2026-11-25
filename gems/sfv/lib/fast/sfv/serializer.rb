# frozen_string_literal: true

module Fast
  module SFV
    # The RFC 9651 §4.1 emit path: module functions appending bytes into
    # one output String, which is the only object an emission allocates —
    # append-only, byte-index validation, no pattern machinery (the parse
    # path's own discipline). The Ruby type of a value IS its wire-type
    # tag: an Integer is an integer, a Float a decimal, a Token a token,
    # a String an sf-string unless it is tagged ASCII-8BIT, which is a
    # byte sequence — the content never decides the type, so "foo" the
    # String stays a quoted sf-string and Fast::SFV::Token.new("foo") a
    # bare token (RFC 9213 §2.1 forbids inferring a type from content),
    # and the Token arm is matched before the String arm in the dispatch
    # because a Token IS a String — a binary-tagged Token still emits
    # bare. Everything non-serializable raises SerializeError carrying
    # the output's byte offset where the emit stopped; the grammar byte
    # classes are the parse path's (parser.rb owns them, the emit path
    # reads the same sets from the value side).
    module Serializer
      # The wire grammar classes the emit path validates against: a key's
      # first byte and continuation (§4.1.1.3), a token's first byte and
      # continuation (§4.1.7) — the same sets the parser reads.
      KEY_FIRST = Parser::KEY_FIRST
      KEY_BODY = Parser::KEY_BODY
      TOKEN_FIRST = Parser::TOKEN_FIRST
      TOKEN_BODY = Parser::TOKEN_BODY
      # One DIGIT of a decimal's Float#to_s digits (§4.1.5).
      DIGIT = Parser::DIGIT
      # The byte a display string always percent-escapes, and the DQUOTE
      # both wire forms share (§4.1.11 step 4.1.1).
      PERCENT = Parser::PERCENT
      DQUOTE = Parser::DQUOTE
      # The two bytes an sf-string escape carries a backslash for: DQUOTE
      # and backslash (§4.1.6 step 4.1) — the parse path's own class.
      STRING_ESCAPE = Parser::STRING_ESCAPE
      # The bytes of the decimal walk's two non-digit characters: the
      # exponent marker and its "+" sign (a "-" is Parser::HYPHEN, the
      # point Parser::PERIOD).
      EXPONENT = 0x65
      PLUS = 0x2B
      # The base64 alphabet of a byte sequence (§4.1.8, RFC 4648 §4):
      # 6-bit groups index it, getbyte hands back the byte to append.
      BASE64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
      # The lowercase hex digits of a display-string percent escape
      # (§4.1.11 step 4.1.2).
      HEX = "0123456789abcdef"
      # 10 to the 0th..18th power: the places an integer's base-10 digits
      # are spelled against, and the digit-count bound a Float#to_s
      # mantissa (at most 17 significant digits) can never pass.
      POWERS = (0..18).map { |power| 10**power }.freeze
      # The decimal range of §4.1.4 step 1.
      INTEGER_MAX = 999_999_999_999_999

      module_function

      # The wire form of one Item (§4.1.3) — serialize_item's answer and
      # Item#to_s: the bare item, then its parameters.
      def item_string(item)
        output = String.new
        emit_item(output, item)
        output.force_encoding(Encoding::US_ASCII)
      end

      # The wire form of one Inner List (§4.1.1.1) — InnerList#to_s.
      def inner_list_string(inner_list)
        output = String.new
        emit_inner_list(output, inner_list)
        output.force_encoding(Encoding::US_ASCII)
      end

      # The wire form of one List (§4.1.1) — serialize_list's answer. The
      # empty case never reaches here: the entry point answers nil (§4.1
      # step 1, the omitted field).
      def list_string(list)
        output = String.new
        first = true
        list.each do |member|
          if first
            first = false
          else
            output << ", "
          end
          if member.is_a?(Item)
            emit_item(output, member)
          elsif member.is_a?(InnerList)
            emit_inner_list(output, member)
          else
            fail_serialize(output, "a list member must be an Item or an InnerList (got #{shape(member)})")
          end
        end
        output.force_encoding(Encoding::US_ASCII)
      end

      # The wire form of one Dictionary (§4.1.2) — serialize_dict's
      # answer, with the empty case omitted by the entry point.
      def dictionary_string(dictionary)
        output = String.new
        first = true
        dictionary.each do |key, member|
          if first
            first = false
          else
            output << ", "
          end
          emit_key(output, key)
          if member.is_a?(InnerList)
            output << "="
            emit_inner_list(output, member)
          elsif member.is_a?(Item)
            if member.value.equal?(true)
              emit_parameters(output, member.params)
            else
              output << "="
              emit_item(output, member)
            end
          else
            fail_serialize(output, "a dictionary value must be an Item or an InnerList (got #{shape(member)})")
          end
        end
        output.force_encoding(Encoding::US_ASCII)
      end

      # The wire form of one Date (§4.1.10) — Date#to_s.
      def date_string(date)
        output = String.new
        emit_date(output, date)
        output.force_encoding(Encoding::US_ASCII)
      end

      # The wire form of one Display String (§4.1.11) —
      # DisplayString#to_s.
      def display_string_string(display_string)
        output = String.new
        emit_display_string(output, display_string)
        output.force_encoding(Encoding::US_ASCII)
      end

      # §4.1.3 Serializing an Item: the bare item, then its parameters.
      def emit_item(output, item)
        emit_bare_item(output, item.value)
        emit_parameters(output, item.params)
      end

      # §4.1.1.1 Serializing an Inner List: "(", the items joined by
      # single SPs, ")", then the list's own parameters after the close.
      # An empty inner list is "()" — only the top level omits a field.
      def emit_inner_list(output, inner_list)
        output << "("
        items = inner_list.items
        fail_serialize(output, "an inner list's items must be an Array (got #{shape(items)})") unless items.is_a?(Array)

        first = true
        items.each do |item|
          if first
            first = false
          else
            output << " "
          end
          fail_serialize(output, "an inner list member must be an Item (got #{shape(item)})") unless item.is_a?(Item)

          emit_item(output, item)
        end
        output << ")"
        emit_parameters(output, inner_list.params)
      end

      # §4.1.1.2 Serializing Parameters: ";" then the key, then "= value"
      # unless the value is Boolean true — the ";key" short form. The
      # Hash's iteration order is the wire order.
      def emit_parameters(output, params)
        fail_serialize(output, "parameters must be a Hash (got #{shape(params)})") unless params.is_a?(Hash)

        params.each do |key, value|
          output << ";"
          emit_key(output, key)
          unless value.equal?(true)
            output << "="
            emit_bare_item(output, value)
          end
        end
      end

      # §4.1.1.3 Serializing a Key: the first byte lcalpha or "*", the
      # continuation KEY_BODY — the class the parse path reads; then the
      # key's bytes are appended whole.
      def emit_key(output, key)
        fail_serialize(output, "a key must be a String (got #{shape(key)})") unless key.is_a?(String)

        size = key.bytesize
        fail_serialize(output, "a key must not be empty") if size.zero?
        fail_serialize(output, "a key must start with a lowercase letter or '*'") unless KEY_FIRST[key.getbyte(0)]

        index = 1
        while index < size
          unless KEY_BODY[key.getbyte(index)]
            fail_serialize(output, "a key may only carry lcalpha, DIGIT, '_', '-', '.' and '*'")
          end
          index += 1
        end
        output << key
      end

      # §4.1.3.1 Serializing a Bare Item: the Ruby type is the dispatch —
      # Integer, Float, Token (a token: the arm is matched before the
      # String arm, because a Token IS a String), String (an sf-string,
      # or a byte sequence when tagged ASCII-8BIT), true, false, Date
      # and DisplayString. Anything else fails — a Symbol is wrong-typed
      # input now that tokens are Tokens; there is no coercion and no
      # content inference.
      def emit_bare_item(output, value)
        case value
        when Integer
          emit_integer(output, value)
        when Float
          emit_decimal(output, value)
        when Token
          emit_token(output, value)
        when String
          if value.encoding == Encoding::ASCII_8BIT
            emit_byte_sequence(output, value)
          else
            emit_string(output, value)
          end
        when true
          output << "?1"
        when false
          output << "?0"
        when Date
          emit_date(output, value)
        when DisplayString
          emit_display_string(output, value)
        else
          fail_serialize(output, "a bare item must be one of the eight bare types (got #{shape(value)})")
        end
      end

      # §4.1.4 Serializing an Integer: "-" when negative, then the
      # base-10 digits spelled by division against the POWERS table — no
      # String fragment per value. Zero is "0"; the range is the 15-digit
      # one.
      def emit_integer(output, value)
        magnitude = value.abs
        fail_serialize(output, "an integer is at most 999999999999999") if magnitude > INTEGER_MAX
        output << "-" if value.negative?
        emit_digits(output, magnitude)
      end

      # Spells +magnitude+ in base 10, most significant digit first: the
      # shared tail of integer, decimal and date emission.
      def emit_digits(output, magnitude)
        power = 15
        power -= 1 while power.positive? && POWERS[power] > magnitude
        while power >= 0
          output << (0x30 + magnitude / POWERS[power])
          magnitude %= POWERS[power]
          power -= 1
        end
      end

      # §4.1.5 Serializing a Decimal: the digits AS WRITTEN — the
      # shortest round-trip decimal Float#to_s spells (the corpus's tie
      # records pin this reading over the binary double's rounding:
      # 0.5015 writes "0.502") — rounded to three fraction places, ties
      # to even; at most 12 integer digits after the rounding; the
      # fraction keeps its leading zeros and drops trailing zeros, "0"
      # when it is zero. The one unavoidable temporary is the Float#to_s
      # text the digits are read from; the walk accumulates the mantissa
      # in place, exponent form included.
      def emit_decimal(output, value)
        fail_serialize(output, "a decimal must be finite") unless value.finite?

        text = value.to_s
        size = text.bytesize
        index = 0
        negative = text.getbyte(0) == Parser::HYPHEN
        index += 1 if negative
        mantissa = 0
        while index < size && DIGIT[text.getbyte(index)]
          mantissa = mantissa * 10 + (text.getbyte(index) - 0x30)
          index += 1
        end
        fraction = 0
        if text.getbyte(index) == Parser::PERIOD
          index += 1
          while index < size && DIGIT[text.getbyte(index)]
            mantissa = mantissa * 10 + (text.getbyte(index) - 0x30)
            fraction += 1
            index += 1
          end
        end
        exponent = 0
        if text.getbyte(index) == EXPONENT
          index += 1
          exponent_negative = text.getbyte(index) == Parser::HYPHEN
          index += 1 if exponent_negative || text.getbyte(index) == PLUS
          while index < size && DIGIT[text.getbyte(index)]
            exponent = exponent * 10 + (text.getbyte(index) - 0x30)
            index += 1
          end
          exponent = -exponent if exponent_negative
        end
        scale = fraction - exponent
        if scale > 21
          # A factor past 10^18: the mantissa (at most 18 digits) is
          # under half of it, so the rounding lands on zero.
          mantissa = 0
          scale = 3
        elsif scale > 3
          factor = 10**(scale - 3)
          rounded = mantissa / factor
          remainder = mantissa - rounded * factor
          half = factor / 2
          # Ties to even, on the as-written digits (§4.1.5 step 2).
          rounded += 1 if remainder > half || (remainder == half && rounded.odd?)
          mantissa = rounded
          scale = 3
        end

        # §4.1.5 step 3: at most 12 significant digits left of the point,
        # after the rounding — a carry may push the count over.
        integer_digits = digit_count(mantissa) - scale
        integer_digits = 1 if integer_digits < 1
        fail_serialize(output, "a decimal is at most 12 integer digits") if integer_digits > 12

        # §4.1.5 steps 5-9: the sign of the rounded value, the integer
        # component ("0" at zero), the point, then the fraction.
        output << "-" if negative && mantissa.positive?
        if scale.negative?
          emit_digits(output, mantissa)
          zeros = -scale
          while zeros.positive?
            output << "0"
            zeros -= 1
          end
        else
          emit_digits(output, mantissa / POWERS[scale])
        end
        output << "."
        fraction = scale.negative? ? 0 : mantissa % POWERS[scale]
        if fraction.zero?
          output << "0"
        else
          places = scale
          places -= 1 while places.positive? && (fraction % 10).zero?
          power = places - 1
          while power >= 0
            output << (0x30 + fraction / POWERS[power] % 10)
            power -= 1
          end
        end
      end

      # §4.1.6 Serializing a String: DQUOTE-delimited, a backslash
      # escapes only DQUOTE and backslash, every byte SP or VCHAR —
      # 0x20-0x7e. The content is appended whole when nothing needs
      # escaping, in runs between escapes when something does.
      def emit_string(output, value)
        output << "\""
        size = value.bytesize
        start = 0
        escaped = false
        index = 0
        while index < size
          byte = value.getbyte(index)
          if STRING_ESCAPE[byte]
            output << value.byteslice(start, index - start) if index > start
            output << "\\" << byte
            start = index + 1
            escaped = true
          elsif byte < Parser::SP || byte > 0x7E
            fail_serialize(output, "a string may only carry SP and printable ASCII")
          end
          index += 1
        end
        output << (escaped ? value.byteslice(start, size - start) : value)
        output << "\""
      end

      # §4.1.7 Serializing a Token: ALPHA or "*" first, the continuation
      # TOKEN_BODY — validated on the Token's own bytes, then appended
      # whole: the constructor already guaranteed this grammar at the
      # boundary, so the walk is a strict sender's defensive re-check.
      def emit_token(output, value)
        size = value.bytesize
        fail_serialize(output, "a token must not be empty") if size.zero?
        fail_serialize(output, "a token must start with ALPHA or '*'") unless TOKEN_FIRST[value.getbyte(0)]

        index = 1
        while index < size
          fail_serialize(output, "a token may only carry tchar, ':' and '/'") unless TOKEN_BODY[value.getbyte(index)]

          index += 1
        end
        output << value
      end

      # §4.1.8 Serializing a Byte Sequence: ":" + the RFC 4648 §4 base64
      # of the bytes, padded with "=" (the pad bits are zero by
      # construction, the shifts below fill with zeros) + ":". Three
      # bytes spell four alphabet bytes, the 2-byte tail spells three and
      # one pad, the 1-byte tail two and two.
      def emit_byte_sequence(output, value)
        output << ":"
        size = value.bytesize
        index = 0
        while index + 3 <= size
          group = (value.getbyte(index) << 16) | (value.getbyte(index + 1) << 8) | value.getbyte(index + 2)
          output << BASE64.getbyte(group >> 18) << BASE64.getbyte((group >> 12) & 0x3F)
          output << BASE64.getbyte((group >> 6) & 0x3F) << BASE64.getbyte(group & 0x3F)
          index += 3
        end
        remaining = size - index
        if remaining == 2
          group = (value.getbyte(index) << 16) | (value.getbyte(index + 1) << 8)
          output << BASE64.getbyte(group >> 18) << BASE64.getbyte((group >> 12) & 0x3F)
          output << BASE64.getbyte((group >> 6) & 0x3F) << "="
        elsif remaining == 1
          group = value.getbyte(index) << 16
          output << BASE64.getbyte(group >> 18) << BASE64.getbyte((group >> 12) & 0x3F) << "=="
        end
        output << ":"
      end

      # §4.1.10 Serializing a Date: "@" + the integer form of #value —
      # the Integer range applies; @0 at zero.
      def emit_date(output, value)
        output << "@"
        number = value.value
        fail_serialize(output, "a date's value must be an Integer (got #{shape(number)})") unless number.is_a?(Integer)

        emit_integer(output, number)
      end

      # §4.1.11 Serializing a Display String: #value UTF-8-encoded (a
      # String that cannot be read as Unicode text fails), then `%"`,
      # per byte: "%", DQUOTE and the control/high bytes as "%" plus two
      # lowercase hex digits, every other byte literal, then `"`. The
      # literal runs are appended whole when nothing needs escaping.
      def emit_display_string(output, value)
        text = value.value
        unless text.is_a?(String)
          fail_serialize(output, "a display string's value must be a String (got #{shape(text)})")
        end
        if text.encoding != Encoding::UTF_8
          begin
            text = text.encode(Encoding::UTF_8)
          rescue Encoding::UndefinedConversionError, Encoding::InvalidByteSequenceError, Encoding::ConverterNotFoundError
            fail_serialize(output, "a display string must be Unicode text")
          end
        end
        fail_serialize(output, "a display string must be Unicode text") unless text.valid_encoding?

        output << "%\""
        size = text.bytesize
        start = 0
        escaped = false
        index = 0
        while index < size
          byte = text.getbyte(index)
          if byte == PERCENT || byte == DQUOTE || byte < Parser::SP || byte > 0x7E
            output << text.byteslice(start, index - start) if index > start
            output << "%" << HEX.getbyte(byte >> 4) << HEX.getbyte(byte & 0xF)
            start = index + 1
            escaped = true
          end
          index += 1
        end
        output << (escaped ? text.byteslice(start, size - start) : text)
        output << "\""
      end

      # The number of base-10 digits of +magnitude+ (1 at zero): the
      # POWERS place it reaches, bounded by the 18 a Float#to_s mantissa
      # can never pass.
      def digit_count(magnitude)
        count = 1
        count += 1 while count < 19 && POWERS[count] <= magnitude
        count
      end

      # The class of +value+ for an error message, or a placeholder when
      # the value has none (a BasicObject descendant).
      def shape(value)
        defined?(value.class) ? value.class : "a classless object"
      end

      # Raises the positioned SerializeError: the reason, and the byte
      # offset into the output built so far where the emit stopped.
      def fail_serialize(output, reason)
        offset = output.bytesize
        raise SerializeError.new("#{reason} at offset #{offset}", offset)
      end

      # Raises at offset 0: the top-level input shape is wrong before
      # anything was emitted.
      def fail_shape(expected, got)
        raise SerializeError.new("#{expected} is required (got #{shape(got)})", 0)
      end
    end

    private_constant :Serializer

    module_function

    # Serializes one RFC 9651 Item (§4.1, field_type "item") — the
    # canonical §4.1.3 form, the bare item then its parameters, as a
    # fresh US-ASCII String the caller owns.
    #
    # Strict: a non-Item input, or any non-serializable value inside it,
    # raises SerializeError with the byte offset into the output built
    # so far. There is no coercion and no content inference: a String
    # value is an sf-string whatever it spells, a Fast::SFV::Token a
    # token (a Symbol is wrong-typed input and raises), an ASCII-8BIT
    # String a byte sequence.
    def serialize_item(item)
      Serializer.fail_shape("an Item", item) unless item.is_a?(Item)

      Serializer.item_string(item)
    end

    # Serializes an RFC 9651 List (§4.1, field_type "list") — the
    # canonical §4.1.1 form of an Array of Items and InnerLists, as a
    # fresh US-ASCII String, or nil for the empty List (§4.1 step 1: an
    # empty container omits the field entirely).
    #
    # Strict: a non-Array input or an unwrapped member raises
    # SerializeError; an Item is never empty, so only the containers
    # answer nil.
    def serialize_list(list)
      Serializer.fail_shape("an Array of Items and InnerLists", list) unless list.is_a?(Array)
      return nil if list.empty?

      Serializer.list_string(list)
    end

    # Serializes an RFC 9651 Dictionary (§4.1, field_type "dictionary") —
    # the canonical §4.1.2 form of an ordered Hash of String keys to
    # Items and InnerLists, as a fresh US-ASCII String, or nil for the
    # empty Dictionary (the omitted field). A member whose Item value is
    # Boolean true uses the valueless short form.
    #
    # Strict: a non-Hash input, a Symbol key or an unwrapped value
    # raises SerializeError.
    def serialize_dict(dict)
      Serializer.fail_shape("a Hash of String keys to Items and InnerLists", dict) unless dict.is_a?(Hash)
      return nil if dict.empty?

      Serializer.dictionary_string(dict)
    end
  end
end
