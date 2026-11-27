# frozen_string_literal: true

module Fast
  module Priority
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
      check_members!(dict, input)
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

    # The combined field value's region scan, consulted only where an
    # error needs an offset — the clean path pays nothing for
    # positioning. The scan is the substrate's own §4.2 walk (RFC 9651
    # display strings, parameters on the valueless member), so the
    # offset survives the members a private walk would desync on.
    # §4 inverted on the effective members: the two known parameters
    # checked, each error pointed at the value the scan found.
    def check_members!(dict, input)
      urgency = dict["u"]
      check_urgency!(urgency, input) if urgency
      incremental = dict["i"]
      check_incremental!(incremental, input) if incremental
    end

    # §4.1, inverted: a held "u" member is an Item carrying an Integer
    # 0..7.
    def check_urgency!(member, input)
      return if member.is_a?(Item) && member.value.is_a?(Integer) && member.value.between?(0, 7)

      raise ParseError.new("urgency is an Integer 0..7 (got #{shown(member)})", value_offset(input, "u"))
    end

    # §4.2, inverted: a held "i" member is an Item carrying a Boolean
    # — one of the two literals, the identity check the emit path's own
    # short-form test uses, so nothing allocates per member.
    def check_incremental!(member, input)
      return if member.is_a?(Item) && (member.value.equal?(true) || member.value.equal?(false))

      raise ParseError.new("incremental is a Boolean (got #{shown(member)})", value_offset(input, "i"))
    end

    # The byte the effective (last-wins) +key+ member's VALUE starts
    # at in the combined field value: the last occurrence's value
    # start in the substrate's region scan — the member the §4.2
    # last-wins parse kept, the position a semantic ParseError points
    # at. The valueless member's span is empty at its key's end, the
    # position a value would be written at, so it answers the key's
    # end — the same offset the implicit Boolean true always raised
    # at.
    def value_offset(input, key)
      regions = SFV.regions_dict(input)
      offset = nil
      regions.members.each do |member|
        member_key = regions.combined.byteslice(member.key_start, member.key_end - member.key_start)
        offset = member.value_start if member_key == key
      end
      offset
    end

    # What a semantic error shows of the offending member: the bare
    # value when it is an Item (out of range, or an alien type), the
    # member's class when it is not an Item at all — an inner list.
    def shown(member)
      member.is_a?(Item) ? member.value : member.class
    end

    private_class_method :check_members!, :check_urgency!, :check_incremental!, :value_offset, :shown
  end
end
