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

    # The members a fail-closed parse holds: none — the same answer an
    # absent field gives (RFC 9651 §2.2, RFC 9530 §2).
    EMPTY_MEMBERS = {}.freeze
    private_constant :EMPTY_MEMBERS

    # The strict parse's positioning walk: where each member's VALUE
    # sits in the combined field value — the byte offset a semantic
    # ParseError points at. The field value already parsed when this
    # runs, so the walk only tracks the boundaries: members split on
    # commas at inner-list depth zero outside quoted strings (RFC 9651
    # §4.2's separators), a quoted string's commas and parens do not
    # count (§4.2.5's escapes are skipped two bytes), and a member
    # without "=" — the implicit Boolean true — offsets at its key's
    # end, where its value would be written. Every key's offset is
    # recorded, a later occurrence overwriting an earlier one, because
    # Fast::SFV applies §4.2's last-wins before the checks read these
    # offsets — the effective member is the one its value came from.
    class Scan
      # A 256-entry byte class: true for every byte of +spec+ — the
      # byte-table shape Fast::SFV's own scanners walk with.
      def self.byte_class(spec)
        table = Array.new(256, false)
        spec.each_byte { |byte| table[byte] = true }
        table.freeze
      end

      # A Dictionary key's first byte: lcalpha or "*" (§4.2.3.3 step 1).
      KEY_FIRST = byte_class("abcdefghijklmnopqrstuvwxyz*")
      # A key's continuation: lcalpha, DIGIT, "_", "-", "." or "*"
      # (§4.2.3.3) — the class the walk reads a whole key with, the
      # first byte being a member of it.
      KEY_BODY = byte_class("abcdefghijklmnopqrstuvwxyz0123456789_-.*")
      # The optional whitespace around a member separator (§4.2.1).
      OWS = byte_class(" \t")

      COMMA = 0x2C
      EQUALS = 0x3D
      LPAREN = 0x28
      RPAREN = 0x29
      DQUOTE = 0x22
      BACKSLASH = 0x5C

      def initialize(combined)
        @combined = combined
        @size = combined.bytesize
      end

      # One walk answers the value offset of every key the Dictionary
      # parsed — the LAST one seen for each, since the effective member
      # is the last one Fast::SFV kept.
      def offsets
        @offsets = {}
        index = 0
        index = member_at(index) while index < @size
        @offsets
      end

      private

      # Walks one member from +index+ and answers the index the next
      # member starts at: leading OWS, the key, the value — its offset
      # recorded — then the separator. A member that is not followed by
      # a comma ends the walk.
      def member_at(index)
        index += 1 while index < @size && OWS[@combined.getbyte(index)]
        key_start = index
        index += 1 while index < @size && KEY_BODY[@combined.getbyte(index)]
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

      # Records one member's value offset under its key — the bytes the
      # Dictionary itself parsed the same key from, so an equal key
      # overwrites (the last-wins member).
      def record(key_start, key_size, value_offset)
        @offsets[@combined.byteslice(key_start, key_size)] = value_offset
      end

      # The index just past the member VALUE starting at +index+:
      # quoted strings (§4.2.5 — a DQUOTE opens, a backslash escapes the
      # next byte, a DQUOTE closes) and inner-list depth (§4.2.1.1's
      # parens) are tracked, and a comma at depth zero outside a string
      # — the §4.2 member boundary — stops the walk.
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
        # the first offender in Dictionary order raises ParseError
        # naming the key and pointing at that member's VALUE in the
        # combined field value (a member without "=", the implicit
        # Boolean true, at its key's end). Unknown algorithm keys are
        # valid members and pass through untouched, parameters riding
        # along (§2.3 of RFC 9651). TypeError for a wrong input type,
        # as parse.
        def parse!(input)
          dict = SFV.parse_dict(input)
          check_members!(dict, combined(input))
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

        # The field value the scan positions into: the lines joined with
        # ", " — the same RFC 9651 §4.2 combining Fast::SFV.parse_dict
        # applies — a String as given.
        def combined(input)
          input.is_a?(Array) ? input.join(", ") : input
        end

        # The member constraint over a parsed Dictionary: every member
        # an Item whose value satisfies the field's shape — §2/§3's Byte
        # Sequence, §4's Integer 0..10 — the "field-specific
        # constraints" whose violation ignores the whole field under
        # parse. The first offender in Dictionary order is raised at its
        # value's offset.
        def check_members!(dict, field_value)
          return if dict.empty?

          offsets = Scan.new(field_value).offsets
          dict.each do |key, member|
            next if member.is_a?(Item) && value_ok?(member.value)

            raise ParseError.new("#{key}: #{value_rule} (got #{shown(member)})", offsets[key])
          end
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
        raise SerializeError.new("members are a Hash (got #{members.class})", 0) unless members.is_a?(Hash)

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

      # Yields each held algorithm key and its bare value.
      def each
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

        raise SerializeError.new("#{key}: #{self.class.send(:value_rule)} (got #{value.inspect})", 0)
      end

      # The Algorithm Key grammar, RFC 9651 §4.2.3.3 read from the value
      # side: a String whose first byte is lcalpha or "*" and whose
      # bytes continue in lcalpha, DIGIT, "_", "-", "." or "*".
      def check_key(key)
        return if valid_key?(key)

        raise SerializeError.new("#{key.inspect} is not a Structured Fields key", 0)
      end

      # The walk behind check_key — manual and allocation-free, the
      # shape the substrate's own key parse uses.
      def valid_key?(key)
        return false unless key.is_a?(String)

        size = key.bytesize
        return false if size.zero? || !Scan::KEY_FIRST[key.getbyte(0)]

        index = 1
        while index < size
          return false unless Scan::KEY_BODY[key.getbyte(index)]

          index += 1
        end
        true
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
        value.is_a?(String) && !value.is_a?(Token) && value.encoding == BINARY
      end

      # The wording a ParseError or SerializeError carries for a member
      # that breaks the constraint.
      def self.value_rule
        "a Content-Digest value is a Byte Sequence: a String tagged Encoding::ASCII_8BIT"
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
        value.is_a?(String) && !value.is_a?(Token) && value.encoding == BINARY
      end

      # The wording a ParseError or SerializeError carries for a member
      # that breaks the constraint.
      def self.value_rule
        "a Repr-Digest value is a Byte Sequence: a String tagged Encoding::ASCII_8BIT"
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
        value.is_a?(Integer) && value.between?(0, 10)
      end

      # The wording a ParseError or SerializeError carries for a member
      # that breaks the constraint.
      def self.value_rule
        "a Want-Content-Digest value is an Integer 0..10"
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
        value.is_a?(Integer) && value.between?(0, 10)
      end

      # The wording a ParseError or SerializeError carries for a member
      # that breaks the constraint.
      def self.value_rule
        "a Want-Repr-Digest value is an Integer 0..10"
      end
      private_class_method :value_ok?, :value_rule
    end
  end
end
