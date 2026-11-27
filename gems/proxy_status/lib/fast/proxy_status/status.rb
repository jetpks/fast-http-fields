# frozen_string_literal: true

module Fast
  class ProxyStatus
    # The shared List engine (Fast::ProxyStatus::ListField): this field
    # includes it and answers its three private class hooks below —
    # member_class (the Hop), empty_value (the shared frozen empty
    # value) and field_label (the word the member errors carry). What
    # stays in this file is Proxy-Status's own: §2's trailer-promotion
    # machinery with its Promotion answer, the hops reader that names
    # the engine's members ivar, and the shared empty value.
    include ListField

    class << self
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
          header_hops.nil? ? nil : from_members(replaced),
          remaining.empty? ? nil : from_members(remaining)
        )
      end

      private

      # The engine's member-class hook: §2's member.
      def member_class
        Hop
      end

      # The engine's empty-value hook: the shared frozen empty value.
      def empty_value
        EMPTY
      end

      # The engine's field-label hook: the word the member errors
      # carry.
      def field_label
        "Proxy-Status"
      end

      # A field argument as received, the hops form: nil for the absent
      # field, an existing value's hops (no re-parse), a String or
      # Array of lines parsed leniently. TypeError for anything else.
      def held_hops(input)
        case input
        when nil
          nil
        when ProxyStatus
          input.hops
        else
          parse(input).hops
        end
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
    # closest to the user agent. The engine's members ivar, named.
    def hops
      @members
    end

    # The shared frozen empty value: the answer an absent, malformed
    # or constraint-violating field parses to — one object, stable
    # identity. Defined at the end of the class body because the
    # constant's initializer calls new, and initialize and the engine's
    # hooks are defined above; the valid empty List ("") parses to a
    # FRESH empty value, equal by the canonical wire form.
    EMPTY = new([])
    private_constant :EMPTY
  end
end
