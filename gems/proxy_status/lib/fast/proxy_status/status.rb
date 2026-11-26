# frozen_string_literal: true

module Fast
  class ProxyStatus
    # The strict parse's positioning walk: where a member's identifier
    # and a §2.1 parameter's VALUE sit in the combined field value —
    # the byte offsets a member or parameter ParseError points at. The
    # field value already parsed when this runs, so the walk only tracks
    # the boundaries: members split on commas at inner-list depth zero
    # outside quoted strings (RFC 9651 §4.2's separators); a semicolon at
    # depth zero outside a string starts a parameter of the member's
    # top-level item (tokens, byte sequences and numbers cannot carry
    # one; a string's and a display string's semicolons are inside their
    # quotes; an inner list's are inside its parens). The walk runs ONLY
    # where an error needs an offset — the clean paths pay nothing for
    # positioning.
    class Scan
      # A 256-entry byte class: true for every byte of +spec+ — the
      # byte-table shape the family's scanners walk with.
      def self.byte_class(spec)
        table = Array.new(256, false)
        spec.each_byte { |byte| table[byte] = true }
        table.freeze
      end

      # A key's bytes (RFC 9651 §4.2.3.3) — the Hop's own grammar
      # class, the same table the construction's key check reads.
      KEY_BODY = Hop::KEY_BODY
      # The optional whitespace around a member separator (§4.2.1).
      OWS = byte_class(" \t")

      COMMA = 0x2C
      SEMICOLON = 0x3B
      EQUALS = 0x3D
      LPAREN = 0x28
      RPAREN = 0x29
      DQUOTE = 0x22
      BACKSLASH = 0x5C
      SP = 0x20

      def initialize(combined)
        @combined = combined
        @size = combined.bytesize
      end

      # The byte offset of member +index+'s identifier: its first
      # non-OWS byte — where a member ParseError points.
      def member_offset(index)
        pos = skip_ows(0)
        member = 0
        while member < index
          pos = boundary(pos, false) + 1
          pos = skip_ows(pos)
          member += 1
        end
        pos
      end

      # The byte offset of member +index+'s +key+ parameter VALUE:
      # just past the "=" when the parameter carries one, the key's end
      # for the valueless form (the implicit Boolean true, written
      # where a value would be). The LAST occurrence of the key wins —
      # the mirror of the parse's last-wins parameter Hash, whose
      # effective value the check read.
      def param_offset(index, key)
        pos = boundary(member_offset(index), true)
        offset = nil
        while pos < @size && @combined.getbyte(pos) == SEMICOLON
          pos += 1
          pos += 1 while pos < @size && @combined.getbyte(pos) == SP
          key_start = pos
          pos += 1 while pos < @size && KEY_BODY[@combined.getbyte(pos)]
          key_end = pos
          value_offset = key_end
          if pos < @size && @combined.getbyte(pos) == EQUALS
            pos += 1
            value_offset = pos
            pos = boundary(pos, true)
          end
          offset = value_offset if @combined.byteslice(key_start, key_end - key_start) == key
        end
        offset
      end

      private

      # Discards leading OWS.
      def skip_ows(index)
        index += 1 while index < @size && OWS[@combined.getbyte(index)]
        index
      end

      # The index of the next boundary at inner-list depth zero outside
      # a quoted string, starting at +index+: always the "," that ends
      # a member, and — when +params_too+ — the ";" that starts the
      # member's top-level parameters or follows one parameter's value,
      # found first. A quoted string's separators are inside its quotes
      # (§4.2.5, a backslash escapes the next byte), an inner list's
      # are inside its parens (§4.2.1.1).
      def boundary(index, params_too)
        depth = 0
        quoted = false
        while index < @size
          byte = @combined.getbyte(index)
          if quoted
            index += byte == BACKSLASH ? 2 : 1
            quoted = false if byte == DQUOTE
          else
            case byte
            when DQUOTE
              quoted = true
            when LPAREN
              depth += 1
            when RPAREN
              depth -= 1
            when SEMICOLON
              return index if params_too && depth.zero?
            when COMMA
              return index if depth.zero?
            end
            index += 1
          end
        end
        index
      end
    end
    private_constant :Scan

    class << self
      # RFC 9209 §2, the recipient semantics — never raises on field
      # content. A field whose syntax is not a Structured Field Value,
      # or whose List carries ANY member that is not a String or Token,
      # is the ENTIRE field ignored (RFC 9651 §2.2: "When
      # field-specific constraints are violated, the entire field is
      # also ignored, unless the field definition defines other handling
      # requirements" — RFC 9209 §2 defines none for members): the
      # shared frozen empty value, the same answer an absent field
      # gives. Parameters NEVER fail the field: unknown parameters are
      # preserved in the Hop's data and ignored semantically (§2.1:
      # "Unrecognised parameters MUST be ignored"), and a known
      # parameter of a type §2.1 does not allow is likewise preserved
      # and ignored by the typed readers — §2.1.5's own quoted-string
      # error example parses, its error the String the example writes.
      # "" is the valid empty List (RFC 9651 §4.2.1) and parses to a
      # fresh empty value. A String is one field value; an Array is the
      # field's lines, combined with ", " (§4.2) — a List has no
      # last-wins, the members concatenate. A wrong input type is a
      # caller bug and raises TypeError.
      def parse(input)
        walk(input, false)
      rescue ParseError
        EMPTY
      end

      # Strict truth. The RFC 9651 List failure is wrapped with its
      # message and byte offset preserved; then the constraints, the
      # FIRST offender in List order raised positioned: §2's member
      # constraint (a member that is not a String or Token) at the
      # member's identifier — its first non-OWS byte in the combined
      # field value — and the §2.1 parameter constraints at the
      # parameter's VALUE, just past the "=" (the key's end for the
      # valueless form, the implicit Boolean true), the message naming
      # the parameter and the type its section states. Unknown
      # parameters are valid (§2.1) and preserved on the strict path.
      # TypeError for a wrong input type, as parse.
      def parse!(input)
        walk(input, true)
      end

      # The boolean mirror: true exactly when parse! returns — false
      # for malformed content, member violations, wrong-typed §2.1
      # parameters and a wrong input type alike (a caller bug is not
      # field content either). The empty value is true.
      def valid?(input)
        walk(input, true)
        true
      rescue TypeError, ParseError
        false
      end

      # §2's append-yourself, the class form. +input+ is the field as
      # received — a String, an Array of field lines, an existing value
      # reused as held, or nil for a response bearing none — parsed
      # leniently (a malformed upstream field is treated as absent: the
      # proxy starts a fresh list rather than failing the response);
      # this intermediary's +hop+ is appended as the LAST member (§2:
      # closest to the user agent) with the received members preserved
      # in order. Answers a NEW frozen value whose to_s re-emits the
      # whole list canonically. TypeError for a wrong +input+ type (a
      # caller bug); SerializeError for a wrong hop or parameter (field
      # content, the construction boundary).
      def append(input, hop, params = {})
        held_value(input).append(hop, params)
      end

      # §2's trailer-promotion algorithm, spec-exact, over two field
      # arguments read as parse reads them (a String, an Array of
      # lines, a Fast::ProxyStatus used as held, or nil; a malformed
      # field is treated as absent). For each trailer member in order:
      # the first (leftmost) header member whose identifier equals it —
      # "comparing the String or Token character by character without
      # consideration of parameters", which Ruby String content
      # equality IS (a Token equals the String that spells it) — is
      # REPLACED with the trailer member "in its entirety, including
      # any parameters" and the trailer member CONSUMED (the only
      # reading under which step 2's "Remove the Proxy-Status trailer
      # field if empty" is not vacuous); an unmatched member stays.
      # Replacements are sequential, each trailer member matching
      # against the header as it stands. Answers a frozen Promotion:
      # #header nil exactly when the header input was nil (the
      # algorithm only replaces, never adds), #trailer nil exactly when
      # no members remain (absent, unreadable, or every member
      # promoted). TypeError for a wrong input type.
      def promote(header, trailer)
        header_hops = held_hops(header)
        replaced = header_hops&.dup
        remaining = unmatched(replaced, held_hops(trailer))
        Promotion.new(
          header_hops.nil? ? nil : from_hops(replaced),
          remaining.empty? ? nil : from_hops(remaining)
        )
      end

      private

      # The one walk behind parse and parse!: the RFC 9651 List parse,
      # then the member constraint on every member in List order and —
      # only when +strict+ — the §2.1 parameter constraints, the first
      # offender raised positioned. The lenient parse is THIS walk with
      # the parameter checks not applied, never the strict walk
      # rescued: a parameter violation must not drop the field
      # (§2.1.5's own example) while a member violation must (RFC 9651
      # §2.2) — parse rescues the positioned member failure into the
      # empty value, and the shared constraint predicates and Scan keep
      # the two policies' semantics and offsets from drifting. The
      # underlying List failure is wrapped with its message and offset.
      def walk(input, strict)
        members = SFV.parse_list(input)
        from_hops(hops_from_members(members, combined(input), strict))
      rescue SFV::ParseError => e
        raise ParseError.new(e.message, e.offset)
      end

      # The field value the Scan positions into: the lines joined with
      # ", " — the same RFC 9651 §4.2 combining Fast::SFV.parse_list
      # applies — a String as given.
      def combined(input)
        input.is_a?(Array) ? input.join(", ") : input
      end

      # The member walk over a parsed List: §2's constraint on every
      # member, then the §2.1 parameter checks (strict only), the first
      # offender in List order raising positioned — a member's params
      # are checked before the NEXT member, so "good; error=5, 5"
      # raises at the parameter. A manual position counter: the member
      # index the positioning Scan reads.
      def hops_from_members(members, field_value, strict)
        index = 0
        while index < members.size
          member = members[index]
          fail_member!(field_value, index, member) unless Hop.member_ok?(member)
          check_params!(member, field_value, index) if strict
          index += 1
        end
        members.map { |member| Hop.from_item(member) }
      end

      # §2's member constraint, positioned at the member's identifier.
      def fail_member!(field_value, index, member)
        offset = Scan.new(field_value).member_offset(index)
        raise ParseError.new("a Proxy-Status member is a String or Token (got #{shown(member)})", offset)
      end

      # The five §2.1 parameter constraints over one member, in the
      # parameters' wire order: the first offender raises positioned at
      # its VALUE. Unknown parameters are skipped — §2.1: "Unrecognised
      # parameters MUST be ignored" — and preserved.
      def check_params!(member, field_value, index)
        member.params.each do |key, value|
          rule = Hop.param_rule(key)
          next if rule.nil? || Hop.param_ok?(key, value)

          offset = Scan.new(field_value).param_offset(index, key)
          raise ParseError.new("#{key}: the value is #{rule} (got #{value})", offset)
        end
      end

      # What a member error shows of the offender: the bare value when
      # it is an Item (a wrong type), the member's class when it is not
      # an Item at all — an inner list.
      def shown(member)
        member.is_a?(SFV::Item) ? member.value : member.class
      end

      # A field argument as received, the value form: nil for the
      # absent field (the empty value — a fresh list), an existing
      # value reused as held, a String or Array of lines parsed
      # leniently (a malformed field treated as absent). TypeError for
      # anything else.
      def held_value(input)
        return EMPTY if input.nil?
        return input if input.is_a?(ProxyStatus)

        parse(input)
      end

      # A field argument as received, the hops form: nil for the absent
      # field, an existing value's hops (no re-parse), a String or
      # Array of lines parsed leniently. TypeError for anything else.
      def held_hops(input)
        return nil if input.nil?
        return input.hops if input.is_a?(ProxyStatus)

        parse(input).hops
      end

      # §2 step 1's walk: for each trailer member in order, the
      # leftmost match in +replaced+ — the header's private copy, nil
      # when there is no header field (step 1.2's "no matching
      # header_member is found") — is replaced in its entirety and the
      # member consumed; an unmatched member stays. Answers the
      # remaining trailer members in order; +replaced+ is mutated in
      # place (a private copy — the held values are never touched).
      def unmatched(replaced, trailer_hops)
        remaining = []
        (trailer_hops || EMPTY.hops).each do |member|
          index = replaced && leftmost(replaced, member)
          if index
            replaced[index] = member
          else
            remaining << member
          end
        end
        remaining
      end

      # §2 step 1.1: the FIRST (leftmost) member of the header as it
      # stands whose identifier equals +member+'s — String content
      # equality on the values only, parameters ignored. Answers the
      # index, or nil when there is no match. Manual and
      # allocation-free.
      def leftmost(replaced, member)
        value = member.value
        index = 0
        while index < replaced.size
          return index if replaced[index].value == value

          index += 1
        end
        nil
      end

      # The value object behind hops that already passed the checks:
      # the members held as given, no re-validation (the parse path and
      # append/promote build Hops at their own boundaries).
      def from_hops(hops)
        field = allocate
        field.send(:hold, hops)
        field
      end
    end

    # §2's trailer-promotion answer: the promoted header field value
    # and the trailer field that remains. #header is nil exactly when
    # the header input was nil (the algorithm only replaces, never
    # adds); #trailer is nil exactly when no trailer members remain —
    # §2 step 2's "Remove the Proxy-Status trailer field if empty",
    # the members a promotion consumed. Frozen, with class-checked
    # equality on the pair.
    class Promotion
      # The promoted header value, or nil when there was no header
      # field.
      attr_reader :header

      # The trailer value that remains — the unmatched members — or
      # nil when nothing remains.
      attr_reader :trailer

      def initialize(header, trailer)
        @header = header
        @trailer = trailer
        freeze
      end

      def ==(other)
        other.instance_of?(self.class) && header == other.header && trailer == other.trailer
      end
      alias eql? ==

      # Consistent with eql? — the pair's hash.
      def hash
        header.hash ^ trailer.hash
      end

      def inspect
        "#<#{self.class.name} header=#{header.inspect}, trailer=#{trailer.inspect}>"
      end
    end

    # The held members: the frozen Array of Hops in wire order — §2's
    # order, the first member closest to the origin server, the last
    # closest to the user agent.
    attr_reader :hops

    # Strict construction — a sender never puts garbage on the wire.
    # +members+ is an Array of Hops, each validated at its own
    # construction (Hop.new is the boundary); the Array freezes IN
    # PLACE. The empty Array builds the empty value: a sender omits
    # the field entirely.
    def initialize(members)
      check_members!(members)
      hold(members)
    end

    # §2: "The first member represents the intermediary closest to the
    # origin server" — nil when nothing is held.
    def first
      @hops.first
    end

    # §2: "the last member represents the intermediary closest to the
    # user agent" — nil when nothing is held.
    def last
      @hops.last
    end

    # How many members the field holds.
    def size
      @hops.size
    end

    # No members held — an absent field, or one treated as absent.
    def empty?
      @hops.empty?
    end

    # Yields each hop in wire order.
    def each(&block)
      @hops.each(&block)
    end

    # The hop at +index+ — Array semantics (negative indices, nil
    # beyond the ends).
    def [](index)
      @hops[index]
    end

    # §2's append-yourself, the instance form: the received members
    # preserved in order, this intermediary's member appended as the
    # LAST (§2: closest to the user agent). Answers a NEW frozen value;
    # self is never mutated, and to_s re-emits the whole list
    # canonically (non-canonical spacing normalizes through the
    # round-trip). +hop+ is the identifier (a plain String emits
    # quoted, a Token bare), +params+ the §2.1 parameter Hash;
    # SerializeError for a wrong hop or parameter (the construction
    # boundary).
    def append(hop, params = {})
      members = @hops.dup
      members << Hop.new(hop, params)
      self.class.send(:from_hops, members)
    end

    # The canonical wire form: the RFC 9651 §4.1.1 List serialization
    # of the held hops, "" when none are held (a sender omits the
    # field entirely — the same reason Fast::SFV.serialize_list
    # answers nil for the empty List). Never raises: construction
    # validated every member, and a parsed value re-emits its
    # canonical form (the RFC's "; error=" spacing normalizes to
    # ";error=").
    def to_s
      SFV.serialize_list(@hops) || ""
    end

    # Canonical-wire-form equality WITHIN the class: two fields are
    # the same when they serialize the same.
    def ==(other)
      other.instance_of?(ProxyStatus) && to_s == other.to_s
    end
    alias eql? ==

    # Consistent with eql? — the canonical form's hash.
    def hash
      to_s.hash
    end

    def inspect
      wire = to_s
      wire.empty? ? "#<#{self.class.name}>" : "#<#{self.class.name} #{wire}>"
    end

    private

    # The construction boundary: an Array of Hops, each already
    # validated at its own construction.
    def check_members!(members)
      unless members.is_a?(Array)
        reason = "members are an Array of Hops (got #{members.class})"
        raise SerializeError.new(reason, 0)
      end

      members.each { |member| check_member!(member) }
    end

    # One member's boundary: a Hop — its own construction was its
    # validation.
    def check_member!(member)
      raise SerializeError.new("a member is a Hop (got #{member.class})", 0) unless member.is_a?(Hop)
    end

    # The one place the held state is written, then frozen: the hops
    # Array (frozen already on the parse path, frozen in place by a
    # construction).
    def hold(hops)
      @hops = hops.freeze
      freeze
    end

    # The shared frozen empty value: the answer an absent, malformed
    # or constraint-violating field parses to — one object, stable
    # identity. Defined at the end of the class body because the
    # constant's initializer calls new, and initialize is defined
    # above; the valid empty List ("") parses to a FRESH empty value,
    # equal by the canonical wire form.
    EMPTY = new([])
    private_constant :EMPTY
  end
end
