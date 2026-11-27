# frozen_string_literal: true

module Fast
  module ClientCert
    # RFC 9440 §2.2, the Client-Cert field: "This field contains the
    # end-entity certificate used by the client in the TLS handshake"
    # — "Client-Cert is a Byte Sequence with the value of the header
    # encoded as described in Section 2.1", the DER bytes base64-coded
    # and delimited with colons. A singleton field: "It is a singleton
    # header field value as defined in Section 5.5 of [HTTP], which
    # MUST NOT have a list of values or occur multiple times in a
    # request" — the Item grammar enforces that by itself (it consumes
    # exactly one value and fails at the byte after it), so this class
    # carries no list-detection code; an Array of field lines
    # recombines per RFC 9651 §4.2 into exactly that list-shaped
    # failure.
    class Cert
      # Items this class builds carry no parameters, so they all share
      # the one frozen empty Hash — the parse path's own shape.
      EMPTY_PARAMS = {}.freeze
      private_constant :EMPTY_PARAMS

      class << self
        # §2.2 read as RFC 9651 §2.2 recipient semantics — never
        # raises on field content. A field whose syntax is not a
        # Structured Field Value, a list-shaped value (the singleton
        # rule), the empty field, or an Item whose value is not a Byte
        # Sequence is the field treated as ABSENT: nil — no
        # certificate, the unauthenticated connection (RFC 9440 §4:
        # the access-control decision on absence is the caller's).
        # There is no empty-certificate value object: the wire never
        # carries one. Parameters on the Item never fail the field and
        # ride the canonical re-emit. A String is one field value; an
        # Array is the field's lines, combined with ", " (RFC 9651
        # §4.2). A wrong input type is a caller bug and raises
        # TypeError. The substrate failure is rescued raw rather than
        # wrapped: the wrapped error is the strict caller's truth, and
        # the answer is nil either way.
        def parse(input)
          item = SFV.parse_item(input)
          from_item(item) if Checks.byte_sequence?(item.value)
        rescue SFV::ParseError
          nil
        end

        # Strict truth. The RFC 9651 Item failure is wrapped with its
        # message and byte offset preserved; then the §2.1 constraint
        # — the Item's value must be a Byte Sequence — raises
        # ParseError at the value's first non-OWS byte in the combined
        # field value (the §4.2 parse discards leading OWS, so " 5"
        # fails at 1, not 0), the message naming the type §2.1 states.
        # TypeError for a wrong input type, as parse.
        def parse!(input)
          item = SFV.parse_item(input)
          return from_item(item) if Checks.byte_sequence?(item.value)

          raise ParseError.new(
            "Client-Cert: the value is a Byte Sequence (got #{Checks.shown(item)})", value_offset(input)
          )
        rescue SFV::ParseError => e
          raise ParseError.new(e.message, e.offset)
        end

        # The boolean mirror: true exactly when the field carries a
        # certificate — false for malformed content, non-Byte-Sequence
        # items, list-shaped values, the empty field and a wrong input
        # type alike (a caller bug is not field content either).
        def valid?(input)
          !parse(input).nil?
        rescue TypeError
          false
        end

        private

        # The byte the value starts at in the combined field value —
        # where the constraint's ParseError points. Read from the
        # substrate's region scan, consulted only on this error path:
        # the RFC 9651 §4.2 item parse discards the leading SP before
        # the value (a leading HTAB fails the parse before this walk
        # runs, so the value never begins with one), and the region
        # scan applies the same rule, so the offset and the parse
        # cannot disagree.
        def value_offset(input)
          SFV.regions_item(input).members[0].value_start
        end

        # The value object behind an Item that already passed the
        # check: held as parsed, no re-validation, the Item's
        # parameters preserved for the canonical re-emit.
        def from_item(item)
          cert = allocate
          cert.send(:hold, item)
          cert
        end
      end

      # The DER bytes of the end-entity certificate — frozen, tagged
      # ASCII-8BIT, bytewise-comparable from day one:
      # Fast::ClientCert::Cert.parse(value).der == File.binread("client.der").
      attr_reader :der

      # Strict construction — a sender never puts garbage on the wire.
      # +der+ is the DER-encoded certificate as a String tagged
      # ASCII-8BIT and not a Token: the encoding IS the Byte Sequence
      # tag (a UTF-8 String would emit as a quoted sf-string, a Token
      # as a token), and the bytes themselves are NEVER inspected —
      # DER structure is the caller's, nothing in this gem depends on
      # it. The String is frozen IN PLACE as part of the value object
      # — pass a copy if the buffer is reused. Anything else raises
      # SerializeError before anything is emitted.
      def initialize(der)
        unless Checks.byte_sequence?(der)
          raise SerializeError.new("Client-Cert: the value is a Byte Sequence (got #{Checks.shown(der)})", 0)
        end

        hold(SFV::Item.new(der.freeze, EMPTY_PARAMS))
      end

      # The canonical wire form: the RFC 9651 §4.1.3 serialization of
      # the held Item, ":<base64>:" — a parsed value re-emits the
      # parameters it carried, a constructed one carries none. Never
      # raises: the parse and the construction validated everything.
      def to_s
        SFV.serialize_item(@item)
      end

      # Canonical-wire-form equality WITHIN the class: a Cert equals a
      # Cert — never a bare Item — whose serialization matches.
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
        "#<#{self.class.name} #{wire}>"
      end

      private

      # The one place the held state is written, then frozen: the Item
      # (frozen already on the parse path) and the DER it carries.
      def hold(item)
        @item = item
        @der = item.value
        freeze
      end
    end
  end
end
