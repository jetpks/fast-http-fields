# frozen_string_literal: true

module Fast
  module SFV
    # One member's — or one parameter's — place in the combined field
    # value: the byte offsets of its key and its value, and the
    # parameter group that follows the value. A dictionary member's
    # key spans #key_start...#key_end; a list member's and the item's
    # carry no key (#key_start and #key_end are nil). #value_start is
    # the byte the value starts at and #value_end just past its last
    # byte, before any parameters — for the valueless form (§4.2.2
    # step 3's Boolean-true member, §4.2.3.2 step 2.5's parameter),
    # where nothing is written, both sit at the key's end, the
    # position a value would be written at. #params is the frozen
    # Array of the parameters that follow, each param itself a Region
    # with the same span shape and no parameters of its own. #start
    # and #end span the whole region: the key's first byte (a keyless
    # member's value) to the last parameter's value end.
    class Region
      # The key's first byte and just-past-its-last; the value's start
      # and just-past-its-end; the parameter group that follows the
      # value, in wire order; the region's own first byte and the
      # offset just past its last.
      attr_reader :key_start, :key_end, :value_start, :value_end, :params, :start, :end

      def initialize(key_start, key_end, value_start, value_end, params)
        @key_start = key_start
        @key_end = key_end
        @value_start = value_start
        @value_end = value_end
        @params = params
        @start = key_start || value_start
        @end = params.empty? ? value_end : params.last.value_end
        freeze
      end
    end

    # The §4.2 walk that locates every member of a field value in the
    # combined input, without building the values: one Region per
    # dictionary member (every occurrence — the parse's last-wins is
    # the caller's reduction over #members, exactly what a Ruby Hash
    # assignment does), one per list member in List order, one for
    # the item. The walk is the Parser's own grammar — the same byte
    # classes (the Parser's frozen tables, aliased), the same §4.2.x
    # steps and limits, the same strictness: input the parse rejects
    # raises the same positioned ParseError here, and input it
    # accepts answers spans the parse agrees with (the corpus
    # cross-check pins that agreement record by record). This serves
    # the strict and diagnostic paths — the cold walks that position
    # a field's own error at a member's value — never a hot path.
    class Regions
      # The Parser's own byte classes, aliased: the scan reads exactly
      # the grammar tables the parse reads.
      KEY_FIRST = Parser::KEY_FIRST
      KEY_BODY = Parser::KEY_BODY
      TOKEN_FIRST = Parser::TOKEN_FIRST
      TOKEN_BODY = Parser::TOKEN_BODY
      DIGIT = Parser::DIGIT
      B64 = Parser::B64
      HEX = Parser::HEX
      INNER_BOUNDARY = Parser::INNER_BOUNDARY
      STRING_ESCAPE = Parser::STRING_ESCAPE
      OWS = Parser::OWS

      SP = Parser::SP
      COMMA = Parser::COMMA
      SEMICOLON = Parser::SEMICOLON
      COLON = Parser::COLON
      LPAREN = Parser::LPAREN
      RPAREN = Parser::RPAREN
      DQUOTE = Parser::DQUOTE
      BACKSLASH = Parser::BACKSLASH
      HYPHEN = Parser::HYPHEN
      PERIOD = Parser::PERIOD
      EQUALS = Parser::EQUALS
      PERCENT = Parser::PERCENT
      QUESTION = Parser::QUESTION
      AT_SIGN = Parser::AT_SIGN

      # Regions with no parameters share this one frozen Array.
      NO_PARAMS = [].freeze

      # Scans +input+ (a String, or the field's lines as an Array —
      # the one validated FieldValue combine the parse entry points
      # apply) for the +shape+ §4.2 names: :item, :list or
      # :dictionary. Malformed content raises the positioned
      # ParseError the parse raises; a wrong input type raises
      # TypeError; a wrong shape raises ArgumentError.
      def initialize(input, shape)
        @combined = FieldValue.of(input)
        @end = @combined.bytesize
        @pos = 0
        case shape
        when :item then scan_item
        when :list then scan_list
        when :dictionary then scan_dictionary
        else raise ArgumentError, "the shape must be :item, :list or :dictionary, received #{shape.inspect}"
        end
        freeze
      end

      # The combined field value the spans index into: a String input
      # as given, an Array input's lines joined with ", ".
      attr_reader :combined
      # The members in wire order — every dictionary occurrence, each
      # list member, the one item.
      attr_reader :members

      private

      # §4.2 steps 1-8, field_type "item": one member — keyless, the
      # value's span and the item's parameters.
      def scan_item
        check_ascii
        skip_sp
        member = member_region
        skip_sp
        check_end
        @members = [member].freeze
      end

      # §4.2 steps 1-8, field_type "list": one Region per member in
      # List order — every member the parse kept, no reduction to
      # apply. Empty input is the empty list (§4.2.1 step 3).
      def scan_list
        check_ascii
        skip_sp
        @members = []
        while @pos < @end
          @members << member_region
          skip_ows
          break if @pos >= @end

          separator = @combined.getbyte(@pos)
          @pos += 1
          fail_scan("list members are separated by ','") unless separator == COMMA
          skip_ows
          fail_scan("a list may not end with ','") if @pos >= @end
        end
        skip_sp
        check_end
        @members.freeze
      end

      # §4.2 steps 1-8, field_type "dictionary": one Region per
      # member in wire order — a duplicate key keeps every occurrence
      # (§4.2.2's last value wins is the caller's reduction). Empty
      # input is the empty dictionary (§4.2.2 step 3).
      def scan_dictionary
        check_ascii
        skip_sp
        @members = []
        while @pos < @end
          key_start = @pos
          key_end = scan_key
          value_start = key_end
          value_end = key_end
          if byte == EQUALS
            @pos += 1
            value_start = @pos
            value_end = scan_member_value
          end
          params = scan_params
          @members << Region.new(key_start, key_end, value_start, value_end, params)
          skip_ows
          break if @pos >= @end

          separator = @combined.getbyte(@pos)
          @pos += 1
          fail_scan("dictionary members are separated by ','") unless separator == COMMA
          skip_ows
          fail_scan("a dictionary may not end with ','") if @pos >= @end
        end
        skip_sp
        check_end
        @members.freeze
      end

      # One keyless member — a list member or the item: the value
      # (§4.2.1.1's item or inner list) and the parameter group that
      # follows it.
      def member_region
        value_start = @pos
        value_end = scan_member_value
        Region.new(nil, nil, value_start, value_end, scan_params)
      end

      # §4.2.3.2 Parsing Parameters, positioned: ";" then *SP then a
      # key, then "=" and a bare item, or the valueless form — one
      # Region per parameter, its value span the same convention the
      # dictionary's valueless member uses. A duplicate key keeps
      # every occurrence (the last one wins is the caller's
      # reduction).
      def scan_params
        params = nil
        while byte == SEMICOLON
          @pos += 1
          skip_sp
          key_start = @pos
          key_end = scan_key
          value_start = key_end
          value_end = key_end
          if byte == EQUALS
            @pos += 1
            value_start = @pos
            value_end = scan_bare_item
          end
          (params ||= []) << Region.new(key_start, key_end, value_start, value_end, NO_PARAMS)
        end
        (params || NO_PARAMS).freeze
      end

      # Walks a parameter group without building Regions — an
      # inner-list item's parameters are positioned by the member's
      # own spans, so only their extent matters here.
      def skip_params
        while byte == SEMICOLON
          @pos += 1
          skip_sp
          scan_key
          next unless byte == EQUALS

          @pos += 1
          scan_bare_item
        end
      end

      # §4.2.1.1: "(" opens an inner list; anything else is a single
      # item. Answers the offset just past the member value.
      def scan_member_value
        if byte == LPAREN
          scan_inner_list
        else
          scan_bare_item
        end
      end

      # §4.2.1.2 Parsing an Inner List, positioned: items separated by
      # 1*SP only, each item followed by SP or ")"; ")" closes the
      # list — the value ends just past it, its parameters follow as
      # the member's own. The items' parameters are walked, not held.
      def scan_inner_list
        @pos += 1
        while @pos < @end
          skip_sp
          if byte == RPAREN
            @pos += 1
            return @pos
          end

          scan_bare_item
          skip_params
          boundary = byte
          fail_scan("an inner list item must be followed by SP or ')'") unless INNER_BOUNDARY[boundary]
        end
        fail_scan("an inner list must be closed with ')'")
      end

      # §4.2.3.3 Parsing a Key, positioned: lcalpha or "*" first, then
      # the continuation bytes. Answers the offset just past the key.
      def scan_key
        fail_scan("a key must start with a lowercase letter or '*'") unless KEY_FIRST[byte]

        @pos += 1
        @pos += 1 while KEY_BODY[byte]
        @pos
      end

      # §4.2.3.1 Parsing a Bare Item, positioned: dispatch on the
      # first byte, the RFC's own order. Answers the offset just past
      # the bare item.
      def scan_bare_item
        first = byte
        if first == HYPHEN || DIGIT[first]
          scan_number
        elsif first == DQUOTE
          scan_string
        elsif TOKEN_FIRST[first]
          scan_token
        elsif first == COLON
          scan_byte_sequence
        elsif first == QUESTION
          scan_boolean
        elsif first == AT_SIGN
          scan_date
        elsif first == PERCENT
          scan_display_string
        else
          fail_scan("an item must start with a bare item byte")
        end
      end

      # §4.2.6 Parsing a Token, positioned: ALPHA or "*" first, then
      # tchar, ":" or "/". Answers the offset just past the token.
      def scan_token
        @pos += 1
        @pos += 1 while TOKEN_BODY[byte]
        @pos
      end

      # §4.2.4 Parsing an Integer or Decimal, positioned: an optional
      # "-", then DIGITs with at most one ".", the same limits the
      # parse applies. Answers the offset just past the number.
      def scan_number
        @pos += 1 if byte == HYPHEN
        fail_scan("a number must start with a digit") unless DIGIT[byte]

        start = @pos
        period = nil
        while @pos < @end
          current = @combined.getbyte(@pos)
          if DIGIT[current]
            @pos += 1
          elsif period.nil? && current == PERIOD
            fail_scan("a decimal carries at most 12 integer digits") if @pos - start > 12

            period = @pos
            @pos += 1
          else
            break
          end
        end
        number_limits(start, period)
      end

      # The digit limits the parse's own magnitude walk applies: 12
      # integer digits and 3 fraction digits when decimal, 16
      # characters in all, 15 digits when integer.
      def number_limits(start, period)
        if period
          fail_scan("a decimal is at most 16 characters") if @pos - start > 16
          fail_scan("a decimal must end with a fraction digit") if @pos - period == 1
          fail_scan("a decimal carries at most 3 fraction digits") if @pos - period > 4
        elsif @pos - start > 15
          fail_scan("an integer is at most 15 digits")
        end
        @pos
      end

      # §4.2.5 Parsing a String, positioned: DQUOTE-delimited, a
      # backslash escapes only DQUOTE and backslash, every other byte
      # SP or VCHAR. Answers the offset just past the closing quote.
      def scan_string
        @pos += 1
        while @pos < @end
          current = @combined.getbyte(@pos)
          if current == BACKSLASH
            @pos += 1
            fail_scan("a string escape must be followed by a character") if @pos >= @end

            escaped = @combined.getbyte(@pos)
            fail_scan("only '\"' and '\\' may be escaped in a string") unless STRING_ESCAPE[escaped]

            @pos += 1
          elsif current == DQUOTE
            @pos += 1
            return @pos
          elsif current < SP || current > 0x7E
            fail_scan("a string may only carry SP and printable ASCII")
          else
            @pos += 1
          end
        end
        fail_scan("a string must be closed with '\"'")
      end

      # §4.2.10 Parsing a Display String, positioned: `%"` opens and
      # only DQUOTE closes — a backslash is literal content, never an
      # escape (the §4.2.5 escape is the sf-string's rule, not the
      # display string's) — "%" always exactly two lowercase hex
      # digits, every other byte SP or VCHAR, and the content must
      # decode as UTF-8 (§4.2.10 step 4.5). Answers the offset just
      # past the closing quote.
      def scan_display_string
        @pos += 1
        fail_scan("a display string must open with '%\"'") unless byte == DQUOTE

        @pos += 1
        decoded = display_string_content
        unless decoded.nil? || decoded.force_encoding(Encoding::UTF_8).valid_encoding?
          fail_scan("a display string must be valid UTF-8")
        end

        @pos
      end

      # The display string's content bytes from the first percent
      # escape on — nil when there is none, every byte before the
      # first escape being SP or VCHAR, ASCII and outside any
      # multi-byte sequence — with the closing DQUOTE consumed; every
      # other failure raises on the walk.
      def display_string_content
        decoded = nil
        while @pos < @end
          current = @combined.getbyte(@pos)
          fail_scan("a display string may only carry SP and printable ASCII") if current < SP || current > 0x7E

          if current == PERCENT
            @pos += 1
            fail_scan("a display string escape needs two hex digits") if @pos + 1 >= @end

            high = @combined.getbyte(@pos)
            low = @combined.getbyte(@pos + 1)
            fail_scan("a display string escape needs lowercase hex digits") unless HEX[high] && HEX[low]

            (decoded ||= "".b) << (hex_value(high) * 16 + hex_value(low))
            @pos += 2
          elsif current == DQUOTE
            @pos += 1
            return decoded
          else
            decoded << current if decoded
            @pos += 1
          end
        end
        fail_scan("a display string must be closed with '\"'")
      end

      # The value of one lowercase hex digit, already validated by HEX.
      def hex_value(byte)
        byte <= 0x39 ? byte - 0x30 : byte - 0x61 + 10
      end

      # §4.2.7 Parsing a Byte Sequence, positioned: ":" ... ":" over
      # the base64 alphabet, "=" only as the trailing pad, and no
      # lone trailing character. Answers the offset just past the
      # closing ":".
      def scan_byte_sequence
        @pos += 1
        start = @pos
        close = start
        close += 1 while close < @end && @combined.getbyte(close) != COLON
        fail_scan("a byte sequence must be closed with ':'") if close >= @end

        data_end = start
        data_end += 1 while data_end < close && @combined.getbyte(data_end) != EQUALS
        validate_base64(start, data_end, close)
        fail_scan("a byte sequence may not end with a single base64 character") if (data_end - start) % 4 == 1

        @pos = close + 1
      end

      # The characters in start...data_end must be base64, the rest of
      # the run up to +close+ the trailing "=" pad and nothing else.
      def validate_base64(start, data_end, close)
        index = start
        while index < data_end
          fail_scan("a byte sequence may only carry base64 characters") unless B64[@combined.getbyte(index)]

          index += 1
        end
        while index < close
          fail_scan("base64 '=' may only pad the end of the content") unless @combined.getbyte(index) == EQUALS

          index += 1
        end
      end

      # §4.2.8 Parsing a Boolean, positioned: exactly "?1" or "?0".
      # Answers the offset just past the digit.
      def scan_boolean
        @pos += 1
        fail_scan("a boolean is '?' followed by '1' or '0'") if @pos >= @end

        value = @combined.getbyte(@pos)
        @pos += 1
        return @pos if value == 0x31
        return @pos if value == 0x30

        fail_scan("a boolean is '?' followed by '1' or '0'")
      end

      # §4.2.9 Parsing a Date, positioned: "@" then an Integer — a
      # Decimal fails. Answers the offset just past the digits.
      def scan_date
        @pos += 1
        start = @pos
        scan_number
        index = start
        index += 1 while index < @pos && @combined.getbyte(index) != PERIOD
        fail_scan("a date is '@' followed by an integer, not a decimal") if index < @pos

        @pos
      end

      # §4.2 step 1: the whole field value must be ASCII — the same
      # check and the same offset the parse applies, including the
      # bounded walk for a non-ASCII-compatible encoding whose bytes
      # are all ASCII-range (the grammar rejects what the walk cannot).
      def check_ascii
        return if @combined.ascii_only?

        index = 0
        index += 1 while index < @end && @combined.getbyte(index) <= 0x7F
        return if index >= @end

        @pos = index
        fail_scan("the field value must be ASCII")
      end

      # §4.2 steps 6 and 7: trailing SP is fine, anything else fails.
      def check_end
        fail_scan("unexpected content after the value") unless @pos >= @end
      end

      # Discards leading SP (§4.2 steps 2 and 6).
      def skip_sp
        @pos += 1 while @pos < @end && @combined.getbyte(@pos) == SP
      end

      # Discards leading OWS, SP or tab, around the member commas.
      def skip_ows
        @pos += 1 while @pos < @end && OWS[@combined.getbyte(@pos)]
      end

      # The byte at @pos, NUL when the input is exhausted: NUL is in
      # no grammar class, so every table lookup and delimiter
      # comparison fails cleanly at end of input instead of raising.
      def byte
        @pos < @end ? @combined.getbyte(@pos) : 0
      end

      # Raises the positioned ParseError: the reason, and the byte
      # offset into the combined input where the scan stopped.
      def fail_scan(reason)
        raise ParseError.new("#{reason} at offset #{@pos}", @pos)
      end
    end

    module_function

    # Locates the members of an RFC 9651 Item field value (§4.2,
    # field_type "item") in the combined field value: one Region —
    # keyless, the value's span and the item's parameters. The input
    # is a String, or the field's lines as an Array (the one validated
    # FieldValue combine the parse entry points apply). The scan is
    # the parse's own grammar: malformed content raises the same
    # positioned ParseError, a wrong input type the same TypeError.
    def regions_item(input)
      Regions.new(input, :item)
    end

    # Locates every member of an RFC 9651 List (§4.2, field_type
    # "list") in the combined field value: one Region per member in
    # List order — keyless, the value's span (the "(" of an inner
    # list to just past its ")") and the parameters that follow, an
    # inner list's own parameters included. Empty input answers no
    # members. The input and the strictness are as regions_item.
    def regions_list(input)
      Regions.new(input, :list)
    end

    # Locates every member of an RFC 9651 Dictionary (§4.2,
    # field_type "dictionary") in the combined field value: one Region
    # per member in wire order — the key's and the value's spans, and
    # the member's parameters, including the valueless member's
    # (§4.2.2 step 3 parses them: `a;q=1` is legal). A duplicate key
    # keeps every occurrence: reducing #members into a Hash (an
    # ordinary assignment) lands on the effective member exactly.
    # Empty input answers no members. The input and the strictness
    # are as regions_item.
    def regions_dict(input)
      Regions.new(input, :dictionary)
    end
  end
end
