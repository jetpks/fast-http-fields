# frozen_string_literal: true

module Fast
  module Priority
    # The strict parse's positioning walk: where each known member's
    # VALUE sits in the combined field value — the byte offset a §4
    # semantic ParseError points at. The field value already parsed
    # when this runs, so the walk only tracks the boundaries: members
    # split on commas at inner-list depth zero outside quoted strings
    # (RFC 9651 §4.2's separators), a quoted string's commas and
    # parens do not count (§4.2.5's escapes are skipped two bytes), and
    # a member without "=" — the implicit Boolean true — offsets at its
    # key's end, where its value would be written.
    class Scan
      # A 256-entry byte class: true for every byte of +spec+ — the
      # byte-table shape Fast::SFV's own scanners walk with.
      def self.byte_class(spec)
        table = Array.new(256, false)
        spec.each_byte { |byte| table[byte] = true }
        table.freeze
      end

      # A Dictionary key's bytes (RFC 9651 §4.2.3.3: lcalpha, DIGIT,
      # "_", "-", "." and "*"). The first-byte restriction never
      # matters here — the field value already parsed.
      KEY = byte_class("abcdefghijklmnopqrstuvwxyz0123456789_-.*")
      # The optional whitespace around a member separator (§4.2.1).
      OWS = byte_class(" \t")

      COMMA = 0x2C
      EQUALS = 0x3D
      LPAREN = 0x28
      RPAREN = 0x29
      DQUOTE = 0x22
      BACKSLASH = 0x5C
      # The two keys this gem interprets (RFC 9218 §4.1 and §4.2).
      U_KEY = 0x75
      I_KEY = 0x69

      def initialize(combined)
        @combined = combined
        @size = combined.bytesize
      end

      # One walk answers the offsets of the "u" and "i" members'
      # values — the LAST one seen for each, because Fast::SFV applies
      # §4.2's last-wins before the check reads these offsets, so the
      # effective member is the one its value came from.
      def offsets
        @offsets = {}
        index = 0
        index = member_at(index) while index < @size
        @offsets
      end

      private

      # Walks one member from +index+ and answers the index the next
      # member starts at: leading OWS, the key, the value — its offset
      # recorded when the member is "u" or "i" — then the separator.
      # A member that is not followed by a comma ends the walk.
      def member_at(index)
        index += 1 while index < @size && OWS[@combined.getbyte(index)]
        key_start = index
        index += 1 while index < @size && KEY[@combined.getbyte(index)]
        key_end = index
        value_offset = index
        if @combined.getbyte(index) == EQUALS
          index += 1
          value_offset = index
          index = value_end(index)
        end
        record(key_start, key_end - key_start, value_offset)
        index += 1 while index < @size && OWS[@combined.getbyte(index)]
        return @size unless index < @size && @combined.getbyte(index) == COMMA

        index + 1
      end

      # Records a known member's value offset: a one-byte key that
      # spells "u" or "i" (RFC 9218's two registered single-character
      # parameters — anything longer is an unknown member).
      def record(key_start, key_size, value_offset)
        return unless key_size == 1

        case @combined.getbyte(key_start)
        when U_KEY then @offsets["u"] = value_offset
        when I_KEY then @offsets["i"] = value_offset
        end
      end

      # The index just past the member VALUE starting at +index+:
      # quoted strings (§4.2.5 — a DQUOTE opens, a backslash escapes
      # the next byte, a DQUOTE closes) and inner-list depth
      # (§4.2.1.1's parens) are tracked, and a comma at depth zero
      # outside a string — the §4.2 member boundary — stops the walk.
      def value_end(index)
        depth = 0
        quoted = false
        while index < @size
          byte = @combined.getbyte(index)
          if quoted
            index += byte == BACKSLASH ? 2 : 1
            quoted = false if byte == DQUOTE
          else
            case byte
            when DQUOTE then quoted = true
            when LPAREN then depth += 1
            when RPAREN then depth -= 1
            when COMMA then return index if depth.zero?
            end
            index += 1
          end
        end
        index
      end
    end
    private_constant :Scan

    # The RFC 9218 §4 recipient semantics over one field value: one
    # RFC 9651 Dictionary parse through Fast::SFV ("Receivers parse the
    # Dictionary as described in Section 4.2 of [STRUCTURED-FIELDS]"),
    # the §4 member filter over what parsed, and — when the whole field
    # was malformed — the wrapped failure the frame decoders surface as
    # §7's connection-error signal. The lenient answer never raises on
    # field content: the filter drops what §4's MUST-ignore names, and
    # the failure becomes the defaults.
    class Field
      # The held members when the whole field was malformed: none —
      # the §4 defaults, the same members an absent field answers.
      EMPTY_MEMBERS = {}.freeze

      def initialize(input)
        @error = nil
        begin
          @members = filter(SFV.parse_dict(input))
        rescue SFV::ParseError => e
          @members = EMPTY_MEMBERS
          @error = ParseError.new(e.message, e.offset)
        end
      end

      # The wrapped RFC 9651 failure, nil when the field parsed. This
      # is §7's signal for the CALLER: "Failure to parse the Priority
      # Field Value MAY be treated as a connection error" — the caller
      # owns that MAY.
      attr_reader :error

      # The §4 view of the field: the Parameters the recipient reads.
      def parameters
        Parameters.send(:from_members, @members)
      end

      private

      # §4's filter over a parsed Dictionary: "unknown priority
      # parameters, priority parameters with out-of-range values, or
      # values of unexpected types MUST be ignored" — unknown members
      # pass through as parsed, an out-of-range or wrong-typed "u" or
      # "i" is dropped (never re-emitted), the rest are kept. The
      # parsed Hash is fresh and frozen, so it IS the members Hash when
      # nothing is ignored; a filtered copy is built only when a member
      # drops.
      def filter(dict)
        return dict unless dict.any? { |key, value| ignored?(key, value) }

        dict.reject { |key, value| ignored?(key, value) }.freeze
      end

      # §4's ignore test for one member: "u" survives only as an Item
      # holding an Integer 0..7 (§4.1), "i" only as an Item holding a
      # Boolean (§4.2); every other member is unknown-parameter
      # passthrough (§4.3's extension design) and always kept.
      def ignored?(key, value)
        case key
        when "u"
          !(value.is_a?(Item) && value.value.is_a?(Integer) && value.value.between?(0, 7))
        when "i"
          !(value.is_a?(Item) && (value.value.equal?(true) || value.value.equal?(false)))
        else
          false
        end
      end
    end
    private_constant :Field

    module_function

    # RFC 9218 §4, the recipient semantics — never raises on field
    # content. A malformed or absent field answers the defaults object
    # (urgency 3, incremental false, no member held, to_s ""); a parsed
    # Dictionary is filtered member by member (§4's MUST-ignore on the
    # "u"/"i" members, unknown members kept as parsed). A String is one
    # field value; an Array is the field's lines, combined with ", "
    # (RFC 9651 §4.2). A non-String, non-Array input is a caller bug
    # and raises TypeError.
    def parse(input)
      Field.new(input).parameters
    end

    # Strict truth. The RFC 9651 Dictionary failure is wrapped with its
    # message and byte offset preserved; then §4 inverted on the
    # effective (last-wins) members — a held "u" that is not an Item
    # with an Integer 0..7 (§4.1), or a held "i" that is not an Item
    # with a Boolean (§4.2), raises ParseError pointing at the member's
    # VALUE in the combined field value (a member without "=", the
    # implicit Boolean true, at its key's end). Unknown members are
    # valid input (§4.3) and pass through untouched. TypeError for a
    # wrong input type, as parse.
    def parse!(input)
      dict = SFV.parse_dict(input)
      check_members!(dict, combined(input))
      Parameters.send(:from_members, dict)
    rescue SFV::ParseError => e
      raise ParseError.new(e.message, e.offset)
    end

    # The boolean mirror: true exactly when parse! returns — false for
    # malformed content, for §4 semantic violations, and for a wrong
    # input type alike (a caller bug is not field content either).
    def valid?(input)
      parse!(input)
      true
    rescue TypeError, ParseError
      false
    end

    # The field value the scan positions into: the lines joined with
    # ", " — the same RFC 9651 §4.2 combining Fast::SFV.parse_dict
    # applies — a String as given.
    def combined(input)
      input.is_a?(Array) ? input.join(", ") : input
    end

    # §4 inverted on the effective members: the two known parameters
    # checked, each error pointed at the value the walk found.
    def check_members!(dict, field_value)
      offsets = Scan.new(field_value).offsets
      urgency = dict["u"]
      check_urgency!(urgency, offsets["u"]) if urgency
      incremental = dict["i"]
      check_incremental!(incremental, offsets["i"]) if incremental
    end

    # §4.1, inverted: a held "u" member is an Item carrying an Integer
    # 0..7.
    def check_urgency!(member, offset)
      return if member.is_a?(Item) && member.value.is_a?(Integer) && member.value.between?(0, 7)

      raise ParseError.new("urgency is an Integer 0..7 (got #{shown(member)})", offset)
    end

    # §4.2, inverted: a held "i" member is an Item carrying a Boolean
    # — one of the two literals, the identity check the emit path's own
    # short-form test uses, so nothing allocates per member.
    def check_incremental!(member, offset)
      return if member.is_a?(Item) && (member.value.equal?(true) || member.value.equal?(false))

      raise ParseError.new("incremental is a Boolean (got #{shown(member)})", offset)
    end

    # What a semantic error shows of the offending member: the bare
    # value when it is an Item (out of range, or an alien type), the
    # member's class when it is not an Item at all — an inner list.
    def shown(member)
      member.is_a?(Item) ? member.value : member.class
    end

    private_class_method :combined, :check_members!, :check_urgency!, :check_incremental!, :shown
  end
end
