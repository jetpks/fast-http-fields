# frozen_string_literal: true

module Fast
  module ClientCert
    # RFC 9440 §2.3, the Client-Cert-Chain field: "the certificate
    # chain used for validation of the end-entity certificate" — a
    # List whose every member is a Byte Sequence (§2.1), "The order is
    # the same as the ordering in TLS". The field "MAY have a list of
    # values or occur multiple times in a request" — an Array of field
    # lines is its native split form (combined per RFC 9651 §4.2, a
    # List concatenates with no last-wins) and #split cuts a held
    # chain back into per-instance lines, the §3.1 note that "for
    # header compression purposes, it might be advantageous to split
    # lists into multiple instances". TLS order is the List's own
    # order — data, preserved exactly by the parse and the emit; the
    # membership rules (the chain "does not itself include the
    # end-entity certificate", "The root certificate MAY be omitted",
    # "Client-Cert-Chain MUST NOT appear unless Client-Cert is also
    # present") are request-level policies over opaque DER bytes —
    # documented, never enforced here.
    class Chain
      # The RFC 9651 value shape a member holds, aliased so the
      # checks and the construction read it by the short name.
      Item = SFV::Item
      private_constant :Item

      # Items this class builds carry no parameters, so they all share
      # the one frozen empty Hash — the parse path's own shape.
      EMPTY_PARAMS = {}.freeze
      private_constant :EMPTY_PARAMS

      class << self
        # §2.3 read as RFC 9651 §2.2 recipient semantics — never
        # raises on field content. A field whose syntax is not a
        # Structured Field Value, or a List carrying ANY member that is
        # not a Byte Sequence, is the ENTIRE field ignored: the shared
        # frozen empty value, the same answer an absent field gives.
        # There is NO member-level filtering — a valid certificate
        # beside a bad one drops with the field, the fail-closed
        # posture RFC 9440 §4's security story demands. "" is the
        # valid empty List and parses to the empty value too.
        # Parameters on the members never fail the field and ride the
        # canonical re-emit. A String is one field value; an Array is
        # the field's lines, combined with ", " (RFC 9651 §4.2). A
        # wrong input type is a caller bug and raises TypeError. The
        # substrate failure is rescued raw rather than wrapped: the
        # wrapped error is the strict caller's truth, and the answer
        # is the empty value either way.
        def parse(input)
          members = SFV.parse_list(input)
          # "" is the valid empty List (RFC 9651 4.2.1): it parses to
          # the shared empty value, not a fresh one.
          return EMPTY if members.empty?
          return EMPTY unless members.all? { |member| member_ok?(member) }

          from_members(members)
        rescue SFV::ParseError
          EMPTY
        end

        # Strict truth. The RFC 9651 List failure is wrapped with its
        # message and byte offset preserved; then the §2.3 member
        # constraint — every member an Item whose value is a Byte
        # Sequence — the FIRST offender in List order raised at that
        # member's first non-OWS byte in the combined field value, the
        # message naming the field and the type §2.3 states. The
        # positioning Scan runs only on this error path. TypeError for
        # a wrong input type, as parse.
        def parse!(input)
          members = SFV.parse_list(input)
          index = 0
          while index < members.size
            member = members[index]
            unless member_ok?(member)
              offset = Scan.new(combined(input)).member_offset(index)
              raise ParseError.new(
                "a Client-Cert-Chain member is a Byte Sequence (got #{Checks.shown(member)})", offset
              )
            end

            index += 1
          end
          from_members(members)
        rescue SFV::ParseError => e
          raise ParseError.new(e.message, e.offset)
        end

        # The boolean mirror: true exactly when the strict parse
        # returns — false for malformed content, member violations and
        # a wrong input type alike (a caller bug is not field content
        # either). The empty List is a Structured Field Value: "" is
        # true.
        def valid?(input)
          parse!(input)
          true
        rescue TypeError, ParseError
          false
        end

        private

        # The §2.3 member constraint: an Item whose value is a Byte
        # Sequence — the same check Cert reads, through the shared
        # Checks seam, so the two fields' boundaries cannot drift.
        def member_ok?(member)
          member.is_a?(Item) && Checks.byte_sequence?(member.value)
        end

        # The field value the Scan positions into: the lines joined
        # with ", " — the same RFC 9651 §4.2 combining
        # Fast::SFV.parse_list applies — a String as given. Computed
        # only on the error path, where the positioning needs it.
        def combined(input)
          input.is_a?(Array) ? input.join(", ") : input
        end

        # The value object behind members that already passed the
        # checks: held as parsed, no re-validation, the members'
        # parameters preserved for the canonical re-emit.
        def from_members(members)
          chain = allocate
          chain.send(:hold, members)
          chain
        end
      end

      # The DER bytes of the chain's certificates in TLS order — a
      # frozen Array of frozen ASCII-8BIT Strings, bytewise-comparable
      # from day one.
      attr_reader :ders

      # Strict construction — a sender never puts garbage on the wire.
      # +ders+ is an Array of DER-encoded certificates, each a String
      # tagged ASCII-8BIT and not a Token — the same constraint the
      # parse reads, through the shared Checks seam, so the two
      # boundaries cannot drift; each String is frozen IN PLACE as
      # part of the value object (pass a copy if the buffer is
      # reused), and the bytes themselves are never inspected. The
      # empty Array builds the empty value: a sender omits the field.
      # Anything else raises SerializeError before anything is
      # emitted.
      def initialize(ders)
        unless ders.is_a?(Array)
          raise SerializeError.new("Client-Cert-Chain members are an Array (got #{ders.class})", 0)
        end

        items = []
        ders.each do |der|
          unless Checks.byte_sequence?(der)
            raise SerializeError.new("a Client-Cert-Chain member is a Byte Sequence (got #{Checks.shown(der)})", 0)
          end

          items << Item.new(der.freeze, EMPTY_PARAMS)
        end
        hold(items)
      end

      # How many certificates the chain carries.
      def size
        @ders.size
      end

      # No certificates held — an absent field, or one treated as
      # absent.
      def empty?
        @ders.empty?
      end

      # Yields each certificate's DER bytes in TLS order; without a
      # block, the Enumerator over them.
      def each(&block)
        @ders.each(&block)
      end

      # The DER at +index+ — Array semantics (negative indices, nil
      # beyond the ends).
      def [](index)
        @ders[index]
      end

      # The canonical wire form: the RFC 9651 §4.1.1 List
      # serialization of the held members — the Byte Sequences joined
      # with ", " — "" when none are held (a sender omits the field
      # entirely, the same reason Fast::SFV.serialize_list answers nil
      # for the empty List). Never raises: the parse and the
      # construction validated every member.
      def to_s
        SFV.serialize_list(@items) || ""
      end

      # The sender-side cut (§2.3: "it might be advantageous to split
      # lists into multiple instances"): a frozen Array of canonical
      # field values, each carrying +per_line+ certificates — one per
      # instance at 1, the whole chain in one value at the size. The
      # lines recombine through the Array entry point:
      # Fast::ClientCert::Chain.parse(chain.split(1)) answers the same
      # chain. +per_line+ is a caller choice, so a non-positive one is
      # a caller bug — ArgumentError, never a field error. The empty
      # chain answers no lines.
      def split(per_line)
        unless per_line.is_a?(Integer) && per_line.positive?
          raise ArgumentError, "per_line is a positive Integer (got #{per_line.inspect})"
        end

        lines = []
        index = 0
        size = @items.size
        while index < size
          lines << SFV.serialize_list(@items[index, per_line])
          index += per_line
        end
        lines.freeze
      end

      # Canonical-wire-form equality WITHIN the class: a Chain equals a
      # Chain — never a Cert, never a bare Array — whose serialization
      # matches.
      def ==(other)
        other.instance_of?(self.class) && to_s == other.to_s
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

      # The one place the held state is written, then frozen: the
      # members as parsed (or as built), and the DERs view derived
      # from them.
      def hold(items)
        @items = items.freeze
        @ders = items.map(&:value).freeze
        freeze
      end

      # The strict parse's positioning walk: where member +index+'s
      # first non-OWS byte sits in the combined field value — the
      # offset a member ParseError points at. The field value already
      # parsed when this runs, so the walk only tracks the member
      # boundaries: members split on commas at inner-list depth zero
      # outside quoted strings (RFC 9651 §4.2's separators), so a
      # comma inside a quoted string (§4.2.5, a backslash escapes the
      # next byte) or inside an inner list's parens (§4.2.1.1) does
      # not split.
      class Scan
        # A 256-entry byte class: true for every byte of +spec+ — the
        # byte-table shape the family's scanners walk with.
        def self.byte_class(spec)
          table = Array.new(256, false)
          spec.each_byte { |byte| table[byte] = true }
          table.freeze
        end

        # The optional whitespace around a member separator (RFC 9651
        # §4.2.1).
        OWS = byte_class(" \t")

        COMMA = 0x2C
        LPAREN = 0x28
        RPAREN = 0x29
        DQUOTE = 0x22
        BACKSLASH = 0x5C

        def initialize(combined)
          @combined = combined
          @size = combined.bytesize
        end

        # The byte offset of member +index+'s first non-OWS byte —
        # where a member ParseError points.
        def member_offset(index)
          pos = skip_ows(0)
          member = 0
          while member < index
            pos = boundary(pos) + 1
            pos = skip_ows(pos)
            member += 1
          end
          pos
        end

        private

        # Discards leading OWS.
        def skip_ows(index)
          index += 1 while index < @size && OWS[@combined.getbyte(index)]
          index
        end

        # The index of the next member boundary at inner-list depth
        # zero outside a quoted string, starting at +index+: the ","
        # that ends a member. A quoted string's commas are inside its
        # quotes (§4.2.5, a backslash escapes the next byte), an inner
        # list's are inside its parens (§4.2.1.1).
        def boundary(index)
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

      # The members a fail-closed parse holds: none — the same answer
      # an absent field gives (RFC 9651 §2.2; §2.3 defines no other
      # handling for members). The shared singleton: every fall and
      # every absent field answer this one frozen value.
      EMPTY = new([])
      private_constant :EMPTY
    end
  end
end
