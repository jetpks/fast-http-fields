# frozen_string_literal: true

module Fast
  module Digest
    # The RFC 9651 value shapes a Digest field holds: every member of
    # the Dictionary is a Fast::SFV::Item carrying the algorithm key's
    # value and its parameters. Aliased here — private to this gem — so
    # the checks and the construction walk read it by the short name.
    Item = SFV::Item
    private_constant :Item

    # A Token is a String, and the Token class is its wire-type tag: the
    # byte-sequence constraint has to refuse it by class or a
    # binary-tagged Token would slip through the encoding check and emit
    # as a token, not a Byte Sequence.
    Token = SFV::Token
    private_constant :Token

    # The Byte Sequence tag: a String tagged ASCII-8BIT IS the Byte
    # Sequence (RFC 9651 §3.3.5 — the encoding is the wire-type tag), so
    # both the member constraint and the construction read the same
    # fact, and a UTF-8 String would emit as a quoted sf-string.
    BINARY = Encoding::ASCII_8BIT
    private_constant :BINARY

    # Items this gem builds carry no parameters, so they all share the
    # one frozen empty Hash — the parse path's own shape.
    EMPTY_PARAMS = {}.freeze
    private_constant :EMPTY_PARAMS

    # A 256-entry byte class: true for every byte of +spec+ — the
    # byte-table shape Fast::SFV's own scanners walk with.
    def self.byte_class(spec)
      table = Array.new(256, false)
      spec.each_byte { |byte| table[byte] = true }
      table.freeze
    end

    # A Dictionary key's first byte: lcalpha or "*" (§4.2.3.3 step 1) —
    # the construction boundary's key grammar, read where a sender's
    # key is checked.
    KEY_FIRST = byte_class("abcdefghijklmnopqrstuvwxyz*")
    # A key's continuation: lcalpha, DIGIT, "_", "-", "." or "*"
    # (§4.2.3.3) — the class the key check reads a whole key with.
    KEY_BODY = byte_class("abcdefghijklmnopqrstuvwxyz0123456789_-.*")

    # The members a fail-closed parse holds: none — the same answer an
    # absent field gives (RFC 9651 §2.2, RFC 9530 §2).
    EMPTY_MEMBERS = {}.freeze
    private_constant :EMPTY_MEMBERS

    # The shared machinery of the four Digest fields: one RFC 9651
    # Dictionary parse through Fast::SFV, the member constraint the
    # field's own RFC 9530 section states, and the frozen value object
    # that holds what parsed. The four subclasses each declare their
    # field name's constraint — a Byte Sequence for the two Integrity
    # fields (§2/§3), an Integer 0..10 for the two preference fields
    # (§4) — through value_ok? and value_rule; everything else (the
    # recipient semantics, the strict truth, the readers, the canonical
    # emit) is this class.
    class Field
      class << self
        # RFC 9530 §2/§3/§4, the recipient semantics — never raises on
        # field content. A malformed field, or a field whose Dictionary
        # carries ANY member violating the field's constraint, is the
        # ENTIRE field ignored (RFC 9651 §2.2: "When field-specific
        # constraints are violated, the entire field is also ignored,
        # unless the field definition defines other handling
        # requirements" — RFC 9530 defines none): the empty value
        # object, the same answer an absent field gives. There is no
        # member-level filtering: a valid member beside a bad one drops
        # with the field. "A recipient MAY ignore any or all digests"
        # (§2/§3) is CALLER policy, never the parse's. A String is one
        # field value; an Array is the field's lines, combined with ",
        # " (RFC 9651 §4.2). A wrong input type is a caller bug and
        # raises TypeError.
        def parse(input)
          parse!(input)
        rescue ParseError
          from_members(EMPTY_MEMBERS)
        end

        # Strict truth. The RFC 9651 Dictionary failure is wrapped with
        # its message and byte offset preserved; then the member
        # constraint applied to the effective (last-wins) Dictionary —
        # the first offender in the combined field value's member order
        # raises ParseError naming the key and pointing at that
        # member's VALUE (a member without "=", the implicit Boolean
        # true, at its key's end). Unknown algorithm keys are valid
        # members and pass through untouched, parameters riding along
        # (§2.3 of RFC 9651). TypeError for a wrong input type, as
        # parse.
        def parse!(input)
          dict = SFV.parse_dict(input)
          check_members!(dict, input)
          from_members(dict)
        rescue SFV::ParseError => e
          raise ParseError.new(e.message, e.offset)
        end

        # The boolean mirror: true exactly when parse! returns — false
        # for malformed content, for constraint violations, and for a
        # wrong input type alike (a caller bug is not field content
        # either). The empty Dictionary parses, so "" is true.
        def valid?(input)
          parse!(input)
          true
        rescue TypeError, ParseError
          false
        end

        private

        # The member constraint over a parsed Dictionary: every member
        # an Item whose value satisfies the field's shape — §2/§3's Byte
        # Sequence, §4's Integer 0..10 — the "field-specific
        # constraints" whose violation ignores the whole field under
        # parse. The first offender in the combined field value's member
        # order is raised at its value's offset: among the violating
        # keys, the one whose effective (last-wins) member appears
        # earliest in the field value, positioned by the substrate's
        # region scan on the error path alone — the clean path pays
        # nothing for positioning.
        def check_members!(dict, input)
          violations = nil
          dict.each do |key, member|
            next if member.is_a?(Item) && value_ok?(member.value)

            violations ||= {}
            violations[key] = member
          end
          raise_positioned!(violations, input) if violations
        end

        # The positioned raise for the violating members: the wire-first
        # offender's effective occurrence — the last one the substrate's
        # region scan recorded for its key, the member the §4.2
        # last-wins parse kept — at that occurrence's value start, where
        # a value would be written for the valueless form.
        def raise_positioned!(violations, input)
          regions = SFV.regions_dict(input)
          offsets = {}
          regions.members.each do |member|
            key = regions.combined.byteslice(member.key_start, member.key_end - member.key_start)
            offsets[key] = member.value_start if violations.key?(key)
          end
          key = violations.keys.min_by { |offender| offsets.fetch(offender) }
          raise ParseError.new("#{key}: #{value_rule}, received #{shown(violations.fetch(key))}", offsets.fetch(key))
        end

        # What a semantic error shows of the offending member: the bare
        # value when it is an Item (wrong type, out of range), the
        # member's class when it is not an Item at all — an inner list.
        def shown(member)
          member.is_a?(Item) ? member.value : member.class
        end

        # The value object behind a Dictionary that already passed the
        # checks: the members held as parsed, no re-validation, the
        # Items' parameters preserved.
        def from_members(members)
          field = allocate
          field.send(:hold, members)
          field
        end
      end

      # The held members: the algorithm key => Fast::SFV::Item view,
      # frozen and ordered — the parse's order, or the construction
      # Hash's. The bare values are the #[] view.
      attr_reader :members

      # The algorithm keys in held order, frozen.
      attr_reader :keys

      # Strict construction — a sender never puts garbage on the wire.
      # +members+ is a Hash of algorithm key => bare value: a String
      # tagged ASCII-8BIT for the Integrity fields (the encoding IS the
      # Byte Sequence tag — a UTF-8 String would emit as a quoted
      # sf-string, so it is refused), an Integer 0..10 for the
      # preference fields. Keys are Structured Fields keys (§1.4: the
      # Algorithm Keys are lowercase Dictionary keys, so "SHA-256" is
      # refused). Value Strings are frozen IN PLACE as part of the value
      # object — pass a copy if the buffer is reused. Anything else
      # raises SerializeError before a member is built. The empty Hash
      # builds the empty value: a sender omits the field.
      def initialize(members = {})
        case members
        when Hash
          nil
        else
          raise SerializeError.new("members must be a Hash, received #{shape(members)}", 0)
        end

        held = {}
        members.each do |key, value|
          check_member(key, value)
          held[key] = Item.new(value.freeze, EMPTY_PARAMS)
        end
        hold(held)
      end

      # The bare value of one algorithm key — the digest bytes, or the
      # preference Integer; nil for an absent key. The day-one idiom
      # holds bytewise: parsed["sha-256"] == Digest::SHA256.digest(body).
      def [](key)
        @members[key]&.value
      end

      # Does the field hold a member under +key+?
      def key?(key)
        @members.key?(key)
      end

      # How many members the field holds.
      def size
        @members.size
      end

      # No members held — an absent or fail-closed field.
      def empty?
        @members.empty?
      end

      # Yields each held algorithm key and its bare value. Without a
      # block, answers an Enumerator over the same pairs — the
      # family's iteration convention; the allocation lands only on
      # that cold path.
      def each
        return to_enum(:each) unless block_given?

        @members.each { |key, item| yield key, item.value }
      end

      # The canonical wire form: the RFC 9651 §4.1.2 Dictionary
      # serialization of the held members, "" when none are held — a
      # sender omits the field entirely, the same reason
      # Fast::SFV.serialize_dict answers nil for the empty Dictionary.
      # Never raises: construction validated everything, and a parsed
      # value re-emits its canonical form (non-canonical spacing
      # normalizes, the erratum's doubled padding re-emits single).
      def to_s
        SFV.serialize_dict(@members) || ""
      end

      # Canonical-wire-form equality WITHIN the field class:
      # other.instance_of?(self.class) && to_s == other.to_s. A
      # ContentDigest never equals a ReprDigest, whatever their bytes —
      # the class is the content-versus-representation distinction the
      # RFC 3230 history demands (§1.3, Appendix E).
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
      # members Hash (frozen already on the parse path) and the keys
      # view derived from it.
      def hold(members)
        @members = members.freeze
        @keys = members.keys.freeze
        freeze
      end

      # Construction's member check: the key is a Structured Fields key,
      # the value the field's shape — the same constraint the parse
      # applies, read at the boundary so no unvalidated value reaches
      # the wire.
      def check_member(key, value)
        check_key(key)
        return if self.class.send(:value_ok?, value)

        raise SerializeError.new("#{key}: #{self.class.send(:value_rule)}, received #{shape(value)}", 0)
      end

      # The class of a value an error message names, or a placeholder
      # when the value has none (a BasicObject descendant) — the
      # message never calls a method on the value it is rejecting.
      def shape(value)
        defined?(value.class) ? value.class : "a classless object"
      end

      # The Algorithm Key grammar, RFC 9651 §4.2.3.3 read from the value
      # side: a String whose first byte is lcalpha or "*" and whose
      # bytes continue in lcalpha, DIGIT, "_", "-", "." or "*".
      def check_key(key)
        return if valid_key?(key)

        raise SerializeError.new("#{shape(key)} is not a Structured Fields key", 0)
      end

      # The walk behind check_key — manual and allocation-free, the
      # shape the substrate's own key parse uses.
      def valid_key?(key)
        case key
        when String
          size = key.bytesize
          return false if size.zero? || !KEY_FIRST[key.getbyte(0)]

          index = 1
          while index < size
            return false unless KEY_BODY[key.getbyte(index)]

            index += 1
          end
          true
        else
          false
        end
      end
    end
    private_constant :Field

    # RFC 9530 §2, the Content-Digest field: a Dictionary whose "value
    # is a Byte Sequence that conveys an encoded version of the byte
    # output produced by the digest calculation" — a digest "calculated
    # using a hashing algorithm applied to the actual message content".
    # The whole RFC 3230 lesson lives in this class's name (§1.3,
    # Appendix E): content is what this field digests, and nothing else.
    # Content-Digest can be sent in a trailer (§2: "In this case,
    # Content-Digest MAY be merged into the header section") — the Array
    # entry point is the combining contract, and the caller owns what
    # §6.3's signature cautions then cover.
    class ContentDigest < Field
      # §2's member constraint: a Byte Sequence — a String tagged
      # ASCII-8BIT and not a Token (the class is the token's tag), the
      # exact shape Fast::SFV emits as ":base64:".
      def self.value_ok?(value)
        case value
        when Token
          false
        when String
          value.encoding == BINARY
        else
          false
        end
      end

      # The wording a ParseError or SerializeError carries for a member
      # that breaks the constraint.
      def self.value_rule
        "a Content-Digest value must be a Byte Sequence: a String tagged Encoding::ASCII_8BIT"
      end
      private_class_method :value_ok?, :value_rule

      # Computes a digest of the CONTENT bytes and constructs the field
      # from it — §2's "actual message content", what Content-Encoding
      # chose. .of on the two Integrity fields is the anti-confusion
      # naming: this one hashes content, ReprDigest.of hashes
      # representation data, and the class-checked equality keeps the
      # two apart even with identical bytes. Raises Error for a key
      # Fast::Digest.compute refuses, TypeError for a non-String input.
      def self.of(algorithm, content)
        new(algorithm => Fast::Digest.compute(algorithm, content))
      end
    end

    # RFC 9530 §3, the Repr-Digest field: the same Dictionary shape,
    # "applied to the entire selected representation data" — what a
    # range request does not deliver, what the selected representation
    # is after Content-Encoding, the empty string when no representation
    # data was sent (§3, §6.3). Repr-Digest can be sent in a trailer
    # (§3: "In this case, Repr-Digest MAY be merged into the header
    # section").
    class ReprDigest < Field
      # §3's member constraint: a Byte Sequence — a String tagged
      # ASCII-8BIT and not a Token, the exact shape Fast::SFV emits as
      # ":base64:".
      def self.value_ok?(value)
        case value
        when Token
          false
        when String
          value.encoding == BINARY
        else
          false
        end
      end

      # The wording a ParseError or SerializeError carries for a member
      # that breaks the constraint.
      def self.value_rule
        "a Repr-Digest value must be a Byte Sequence: a String tagged Encoding::ASCII_8BIT"
      end
      private_class_method :value_ok?, :value_rule

      # Computes a digest of the REPRESENTATION DATA bytes and
      # constructs the field from it — §3's "entire selected
      # representation data", what the RFC 3230 "instance" always meant
      # (§1.3, Appendix E: "Using content for the Digest field is an
      # error that leads to interoperability problems"). Raises Error
      # for a key Fast::Digest.compute refuses, TypeError for a
      # non-String input.
      def self.of(algorithm, representation_data)
        new(algorithm => Fast::Digest.compute(algorithm, representation_data))
      end
    end

    # RFC 9530 §4, the Want-Content-Digest field: a Dictionary whose
    # "value is an Integer that conveys an ascending, relative, weighted
    # preference. It must be in the range 0 to 10 inclusive. 1 is the
    # least preferred, 10 is the most preferred, and a value of 0 means
    # 'not acceptable'." A hint only — "It is not a protocol error if
    # preferences are ignored" — so this class carries no selection
    # helper and no compute: the selection policy is the caller's.
    class WantContentDigest < Field
      # §4's member constraint: an Integer 0..10.
      def self.value_ok?(value)
        case value
        when Integer
          value.between?(0, 10)
        else
          false
        end
      end

      # The wording a ParseError or SerializeError carries for a member
      # that breaks the constraint.
      def self.value_rule
        "a Want-Content-Digest value must be an Integer 0..10"
      end
      private_class_method :value_ok?, :value_rule
    end

    # RFC 9530 §4, the Want-Repr-Digest field: the same Integer 0..10
    # preference Dictionary, soliciting the Repr-Digest field — "the
    # sender would like to receive (via the Repr-Digest field) a
    # representation digest on messages associated with the request URI
    # and representation metadata."
    class WantReprDigest < Field
      # §4's member constraint: an Integer 0..10.
      def self.value_ok?(value)
        case value
        when Integer
          value.between?(0, 10)
        else
          false
        end
      end

      # The wording a ParseError or SerializeError carries for a member
      # that breaks the constraint.
      def self.value_rule
        "a Want-Repr-Digest value must be an Integer 0..10"
      end
      private_class_method :value_ok?, :value_rule
    end
  end
end
