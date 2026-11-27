# frozen_string_literal: true

module Fast
  # RFC 9213 Targeted HTTP Cache Control: the framework of response
  # fields that carry cache directives targeted at a specific class of
  # cache — "a targeted field is an HTTP response header field that has
  # the same semantics as the Cache-Control response header field.
  # However, it has a distinct field name that indicates the target for
  # its cache directives" (§2) — and this class is its value object:
  # the RFC 9651 Dictionary of cache directives with §2.1's
  # type-inference rules read on parse and enforced on emit. It does
  # not include the List engine: a Dictionary's members are key-value,
  # and its leniency is per-directive, not whole-field.
  #
  # The registered instance is FIELD_NAME — §3's CDN-Cache-Control, "a
  # targeted field (Section 2) that allows origin servers to control
  # the behavior of CDN caches interposed between them and clients
  # separately from other caches that might handle the response." The
  # class itself is name-agnostic and carries no "-Cache-Control"
  # suffix matcher: §2.4 — "By convention, targeted fields have the
  # suffix '-Cache-Control' ... However, this suffix MUST NOT be used
  # on its own to identify targeted fields; it is only a convention."
  #
  # §2.2's target-list semantics are cache policy, the caller's
  # context, and are never implemented here: a cache "maintains a
  # target list", "MUST select the first (in target-list order) field
  # with a valid, non-empty value", and "MUST ignore the Cache-Control
  # and Expires header fields in that response" — none of which a
  # single field value can decide.
  #
  # parse is the recipient's view with §2.1's own leniency split: a
  # field that is empty or fails to parse is the ENTIRE field ignored
  # — "If a targeted field in a given response is empty, or a parsing
  # error is encountered, that field MUST be ignored by the cache"
  # (§2.1) — the shared frozen empty value, the same answer an absent
  # field gives; while a member whose value violates the inferred
  # constraints is PRESERVED in the data and FLAGGED: "Implementations
  # SHOULD NOT consume values that violate these inferred constraints"
  # (§2.1) — #violating answers those directive keys, in held order,
  # so the caller can do exactly that, and the rest of the field stays
  # readable. The flag is data, never a wire change: a parsed value
  # re-emits faithfully, violating values included. Parameters on
  # directives are ignored — "Parameters received on cache directives
  # are to be ignored, unless other handling is explicitly specified"
  # (§2.1): never a flag, preserved in the raw member data, re-emitted
  # by a round-trip. A String is one field value; an Array is the
  # field's lines, combined with ", " (RFC 9651 §4.2) — duplicate keys:
  # last value wins, first position kept. A wrong input type is a
  # caller bug and raises TypeError.
  #
  # parse! is strict truth: the Dictionary failure wrapped with its
  # message and byte offset, then the inferred constraints, the FIRST
  # offender in Dictionary order raised positioned at its VALUE.
  # valid? answers the same question with a boolean and never raises.
  #
  # to_s and construction are ALWAYS strict, in every family gem:
  # "Implementations MUST NOT generate values that violate these
  # inferred constraints" (§2.1) — every value one of the five
  # inferred types, a known directive's value carrying its section's
  # type, the keys Structured Fields keys. §2.1's digit-initial rule
  # holds structurally: "string values whose first character is not
  # alphabetic or '*' MUST be generated as Strings so that they are not
  # mistaken for other types" — a plain String always emits quoted,
  # and a Token's own grammar (RFC 9651 §3.3.4, ALPHA or "*" first)
  # refuses the form at its construction, so this class needs no check
  # of its own.
  #
  # The answer is a frozen value object: members (the directive key =>
  # Fast::SFV::Item and InnerList view, parameters preserved), keys,
  # violating, the bare #[] view (an inner list member's raw view is
  # its items — a Dictionary value may be an InnerList, which has no
  # #value), key?, size, empty?, each, the canonical to_s ("" when
  # nothing is held), and class-checked canonical equality. Unknown
  # directives pass through untouched (§2.2: "unrecognized extension
  # directives are ignored").
  class TargetedCacheControl
    # RFC 9651 value shapes aliased here, private to this class, so
    # the checks and the readers read them by the short name.
    Item = SFV::Item
    Token = SFV::Token
    private_constant :Item, :Token

    # The Byte Sequence tag: a String tagged ASCII-8BIT IS the Byte
    # Sequence on the wire (RFC 9651 §3.3.5 — the encoding is the
    # wire-type tag), so the inferred-type constraint reads the same
    # fact, and a UTF-8 String would emit as a quoted sf-string.
    BINARY = Encoding::ASCII_8BIT
    private_constant :BINARY

    # Directives this class builds carry no parameters — §2.1: they
    # "are to be ignored" — so they all share the one frozen empty
    # Hash, the parse path's own shape.
    EMPTY_PARAMS = {}.freeze
    private_constant :EMPTY_PARAMS

    # The family root, one rescue for the whole gem: every
    # Fast::TargetedCacheControl failure descends from
    # Fast::ProxyStatus::Error, so a caller can guard this class and
    # its siblings with one rescue. This class is never raised in its
    # own right — every failure here is either a parse defect or a
    # serialization defect. A wrong input type is a caller bug, not
    # field content: it raises plain TypeError and never this class.
    class Error < ProxyStatus::Error; end

    # A targeted field this gem cannot read. Two shapes meet here: the
    # underlying RFC 9651 Dictionary failed to parse — the failure is
    # wrapped with its message and byte offset preserved — or, under
    # the strict parse, a member broke §2.1's inferred constraints (a
    # known directive of the wrong type, or a value outside the five
    # inferred types), and #offset is the byte position of the
    # offending member's VALUE in the combined field value (just past
    # the "="; the key's end for the valueless form; the LAST
    # occurrence of a duplicated key — the member the last-wins parse
    # kept). The lenient parse never raises it: §2.1 MUSTs the field
    # ignored, and the violating member is preserved and flagged
    # instead.
    class ParseError < Error
      attr_reader :offset

      def initialize(message, offset)
        super(message)
        @offset = offset
      end
    end

    # A value cannot go on the wire: the field under construction breaks
    # §2.1's "Implementations MUST NOT generate values that violate
    # these inferred constraints" — a value outside the five inferred
    # types, a known directive's value of the wrong type, a key outside
    # the Structured Fields key grammar, or members that are not a
    # Hash. #offset is the byte position in the output built so far —
    # 0, because the check runs before anything is emitted; the whole
    # emit path raises this class and never TypeError: on emit the
    # wrongness is in the value being sent, which is field content,
    # not a caller protocol bug.
    class SerializeError < Error
      attr_reader :offset

      def initialize(message, offset)
        super(message)
        @offset = offset
      end
    end

    # §3: "The CDN-Cache-Control response header field is a targeted
    # field (Section 2) that allows origin servers to control the
    # behavior of CDN caches interposed between them and clients
    # separately from other caches that might handle the response." The
    # one registered instance this document defines; the class is
    # name-agnostic otherwise (§2.4's suffix MUST NOT).
    FIELD_NAME = "CDN-Cache-Control"

    # §2.2's MUST-implement five, key => the type its value carries —
    # the types from §2.1's own mapping and the Cache-Control sections
    # it cites (RFC 9111 §5.2.2: max-age "an integer number of
    # seconds", must-revalidate and no-store no argument, no-cache and
    # private "a field-name list" in a quoted string). Frozen public
    # data, its own lookup (a Hash IS its registry's read); the table
    # never gates a parse — an unknown directive parses, is preserved
    # and round-trips (§2.2: "unrecognized extension directives are
    # ignored"; a future registration must not break an old gem
    # version).
    DIRECTIVES = {
      "max-age" => "an Integer",                # 9111 5.2.2.1
      "must-revalidate" => "Boolean true",      # 9111 5.2.2.2
      "no-store" => "Boolean true",             # 9111 5.2.2.5
      "no-cache" => "Boolean true or a String", # 9111 5.2.2.4
      "private" => "Boolean true or a String"   # 9111 5.2.2.7
    }.freeze

    # §2.1's rule for a directive the table does not carry: the mapping
    # the section itself spells — "cache directives that have no value
    # will be mapped to a Boolean ... When the value is a
    # quoted-string, it will be mapped to a String, and when it is a
    # token, it will map to a Token, an Integer, or a Decimal,
    # depending on the content of the value." The wording the
    # ParseError and the SerializeError both carry for a value outside
    # the mapping.
    INFERRED = "one of the inferred types (a Boolean, a String, a Token, an Integer or a Decimal)"

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

    class << self
      # RFC 9213 §2.1, the recipient semantics — never raises on field
      # content. A field that is empty or fails to parse is the ENTIRE
      # field ignored ("If a targeted field in a given response is
      # empty, or a parsing error is encountered, that field MUST be
      # ignored by the cache"): the shared frozen empty value, the same
      # answer an absent field gives. A member whose value violates
      # §2.1's inferred constraints is PRESERVED in the data and
      # FLAGGED — "Implementations SHOULD NOT consume values that
      # violate these inferred constraints" — #violating answers those
      # directive keys in held order, and the rest of the field stays
      # readable. Parameters on directives are ignored: never a flag,
      # preserved in the raw member data, re-emitted by a round-trip.
      # A String is one field value; an Array is the field's lines,
      # combined with ", " (RFC 9651 §4.2) — duplicate keys: last value
      # wins, first position kept. A wrong input type is a caller bug
      # and raises TypeError.
      def parse(input)
        walk(input, false)
      rescue ParseError
        empty_value
      end

      # Strict truth. The RFC 9651 Dictionary failure is wrapped with
      # its message and byte offset preserved; then §2.1's inferred
      # constraints, the FIRST offender in Dictionary order raised
      # positioned at that member's VALUE (just past the "="; the key's
      # end for the valueless form; the LAST occurrence of a duplicated
      # key — the member the last-wins parse kept), the message naming
      # the directive and its rule. TypeError for a wrong input type,
      # as parse.
      def parse!(input)
        walk(input, true)
      end

      # The boolean mirror: true exactly when parse! returns — false
      # for malformed content, violating members and a wrong input type
      # alike (a caller bug is not field content either). The empty
      # value is true: the empty Dictionary is valid RFC 9651 content,
      # and §2.1's empty-ignored MUST governs cache behavior, never the
      # field's syntax.
      def valid?(input)
        walk(input, true)
        true
      rescue TypeError, ParseError
        false
      end

      private

      # The one walk behind parse and parse!: the RFC 9651 Dictionary
      # parse, then §2.1's inferred constraints over the effective
      # (last-wins) Dictionary in held order — the first offender raised
      # positioned under the strict policy, the offenders' keys
      # collected under the lenient one (the flag IS the strict/lenient
      # delta, the one-walk discipline the List fields spell: the checks
      # collect instead of raise). The lenient walk answers the shared
      # empty value for the empty Dictionary too — §2.1: "If a targeted
      # field in a given response is empty, or a parsing error is
      # encountered, that field MUST be ignored by the cache" — while
      # the strict walk answers the strict empty value. The underlying
      # Dictionary failure is wrapped with its message and offset.
      def walk(input, strict)
        dict = SFV.parse_dict(input)
        return empty_value if dict.empty? && !strict

        members_from_dict(dict, input, strict)
      rescue SFV::ParseError => e
        raise ParseError.new(e.message, e.offset)
      end

      # The directive walk over a parsed Dictionary: §2.1's constraints
      # on every member in held order, the first offender in Dictionary
      # order raised positioned under the strict policy, the offenders'
      # keys collected — the SHOULD-NOT-consume set #violating answers —
      # under the lenient one, the member kept in the data either way.
      def members_from_dict(dict, input, strict)
        violations = []
        dict.each do |key, member|
          next if directive_ok?(key, member)

          if strict
            fail_member!(key, member, input)
          else
            violations << key
          end
        end
        from_members(dict, violations)
      end

      # §2.1's constraint, positioned: the offender raised at that
      # member's VALUE in the combined field value. The offset comes
      # from the substrate's region scan — consulted only on this
      # error path, so the clean and lenient paths pay nothing for
      # positioning — and the scan is the substrate's own §4.2 walk
      # (RFC 9651 display strings, parameters on the valueless
      # member), so it survives the members a private walk would
      # desync on.
      def fail_member!(key, member, input)
        raise ParseError.new(
          "#{key}: the value must be #{rule_for(key)}, received #{shown(member)}", value_offset(input, key)
        )
      end

      # The byte the effective (last-wins) +key+ member's VALUE starts
      # at in the combined field value — the last occurrence of the key
      # in the substrate's region scan, the member the §4.2 last-wins
      # parse kept; the key's end for the valueless form, where a value
      # would be written.
      def value_offset(input, key)
        regions = SFV.regions_dict(input)
        offset = nil
        regions.members.each do |member|
          member_key = regions.combined.byteslice(member.key_start, member.key_end - member.key_start)
          offset = member.value_start if member_key == key
        end
        offset
      end

      # §2.1's constraint for one directive: a known directive (the
      # §2.2 MUST-implement five, or any a future registration adds)
      # carries the type its section states; every directive's value is
      # one of the five inferred types — an inner list, a Byte Sequence,
      # a Date or a Display String is not in §2.1's mapping, so it
      # violates. Parameters never matter here (§2.1: they "are to be
      # ignored"): the member's own params ride along untouched.
      def directive_ok?(key, member)
        return false unless member.is_a?(Item)

        value_ok?(key, member.value)
      end

      # One directive's value against §2.1's constraints — the read the
      # parse walk and the construction boundary share, so the lenient
      # flag, the strict raise and the emit refusal cannot drift.
      def value_ok?(key, value)
        case key
        when "max-age" then integer_value?(value)
        when "must-revalidate", "no-store" then true_value?(value)
        when "no-cache", "private" then true_value?(value) || plain_string?(value)
        else inferred?(value)
        end
      end

      # §2.1's inferred set: the five types a cache directive's value
      # maps into — Boolean, String, Token, Integer or Decimal. A Byte
      # Sequence (a String tagged ASCII-8BIT), a Date, a Display String
      # or an inner list is outside the mapping.
      def inferred?(value)
        case value
        when true, false, Integer, Float, Token
          true
        when String
          value.encoding != BINARY
        else
          false
        end
      end

      # §2.1's quoted-string mapping: a plain String — not a Token (a
      # different wire type) and not a Byte Sequence.
      def plain_string?(value)
        case value
        when Token
          false
        when String
          value.encoding != BINARY
        else
          false
        end
      end

      # An Integer, as a never-dispatch predicate.
      def integer_value?(value)
        case value
        when Integer
          true
        else
          false
        end
      end

      # Boolean true exactly — the never-dispatch form of the
      # value == true check: these directives carry true, never false.
      def true_value?(value)
        case value
        when true
          true
        else
          false
        end
      end

      # The rule one directive's value must satisfy, worded for the
      # message: the known-directive table's own wording, or the
      # inferred set for a directive the table does not carry.
      def rule_for(key)
        DIRECTIVES[key] || INFERRED
      end

      # What a member error shows of the offender: the bare value when
      # it is an Item (a wrong type), the member's class when it is not
      # an Item at all — an inner list.
      def shown(member)
        member.is_a?(Item) ? member.value : member.class
      end

      # The value object behind a Dictionary that passed the walk: the
      # members held as parsed (Items and InnerLists, parameters
      # preserved), the violating keys held beside them.
      def from_members(members, violations)
        field = allocate
        field.send(:hold, members, violations)
        field
      end

      # The shared frozen empty value: the answer an absent, empty or
      # malformed field parses to — one object, stable identity.
      def empty_value
        EMPTY
      end
    end

    # The held members: the directive key => Fast::SFV::Item (or
    # InnerList) view, frozen and ordered — the parse's order, or the
    # construction Hash's. The bare values are the #[] view; the raw
    # member data — parameters included — is here.
    attr_reader :members

    # The directive keys in held order, frozen.
    attr_reader :keys

    # §2.1's SHOULD-NOT-consume set: the keys whose values violate the
    # inferred constraints, in held order — [] when the field is clean.
    # Data, never a wire change: the values stay in #members and
    # round-trip through to_s.
    attr_reader :violating

    # Strict construction — a sender never puts garbage on the wire:
    # §2.1's "Implementations MUST NOT generate values that violate
    # these inferred constraints." +members+ is a Hash of directive
    # key => bare value: every value one of the five inferred types
    # (a Boolean, an Integer, a Float, a Token or a plain String — a
    # Byte Sequence, a Date, a Display String, an Array or nil is
    # refused), a known directive's value carrying its section's type,
    # the keys Structured Fields keys. Values freeze in place; each
    # member wraps as an Fast::SFV::Item with no parameters (§2.1:
    # parameters "are to be ignored", and no directive defines any, so
    # a sender never invents the syntax). The empty Hash builds the
    # empty value: a sender omits the field entirely — §3.1's own
    # advice, "avoid sending a header field with an empty value, which
    # would be ignored."
    def initialize(members = {})
      check_members!(members)
    end

    # The bare value of one directive — nil for an absent key. An inner
    # list member's raw view is its items (a Dictionary value may be an
    # InnerList, which has no #value).
    def [](key)
      member = @members[key]
      return nil if member.nil?
      return member.value if member.is_a?(Item)

      member.items
    end

    # Does the field hold a member under +key+?
    def key?(key)
      @members.key?(key)
    end

    # How many directives the field holds.
    def size
      @members.size
    end

    # No directives held — an absent, empty or ignored field.
    def empty?
      @members.empty?
    end

    # Yields each held directive key and its bare value, in held
    # order. Without a block, answers an Enumerator over the same
    # pairs — the family's iteration convention; the allocation lands
    # only on that cold path.
    def each
      return to_enum(:each) unless block_given?

      @members.each do |key, member|
        yield key, member.is_a?(Item) ? member.value : member.items
      end
    end

    # The canonical wire form: the RFC 9651 §4.1.2 Dictionary
    # serialization of the held members, "" when none are held (a
    # sender omits the field entirely). Never raises: construction
    # validated every value, and a parsed value re-emits its canonical
    # form — what parsed round-trips faithfully, the violating values
    # included (the flag is data, never a wire change), the explicit
    # ?1 canonicalizing valueless.
    def to_s
      SFV.serialize_dict(@members) || ""
    end

    # Canonical-wire-form equality WITHIN the class: two fields are the
    # same when they serialize the same.
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

    # The construction boundary over a Hash of directive key => bare
    # value, then the one place the held state is written, frozen: the
    # members Hash, the keys view derived from it, the clean flag.
    def check_members!(members)
      case members
      when Hash
        nil
      else
        raise SerializeError.new("members must be a Hash, received #{shape(members)}", 0)
      end

      held = {}
      members.each do |key, value|
        check_key!(key)
        check_value!(key, value)
        held[key] = Item.new(value.freeze, EMPTY_PARAMS)
      end
      hold(held, [])
    end

    # One directive's key at the boundary: the Structured Fields key
    # grammar, RFC 9651 §4.2.3.3 read from the value side — a String
    # whose first byte is lcalpha or "*" and whose bytes continue in
    # lcalpha, DIGIT, "_", "-", "." or "*".
    def check_key!(key)
      return if valid_key?(key)

      raise SerializeError.new("#{shape(key)} is not a Structured Fields key", 0)
    end

    # The walk behind check_key! — manual and allocation-free, the
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

    # The class of a value an error message names, or a placeholder
    # when the value has none (a BasicObject descendant) — the
    # message never calls a method on the value it is rejecting.
    def shape(value)
      defined?(value.class) ? value.class : "a classless object"
    end

    # One directive's value at the boundary: the constraint the parse
    # walk reads (a known directive of its section's type, every value
    # one of the five inferred types), refused here so no unvalidated
    # value reaches the wire.
    def check_value!(key, value)
      return if self.class.send(:value_ok?, key, value)

      raise SerializeError.new("#{key}: the value must be #{rule_for(key)}, received #{shape(value)}", 0)
    end

    # The rule one directive's value must satisfy, worded for the
    # message — the class-level rule_for, reached from the instance.
    def rule_for(key)
      self.class.send(:rule_for, key)
    end

    # The one place the held state is written, then frozen: the members
    # Hash (frozen already on the parse path), the keys view derived
    # from it, and the SHOULD-NOT-consume keys.
    def hold(members, violations)
      @members = members.freeze
      @keys = members.keys.freeze
      @violating = violations.freeze
      freeze
    end

    # The shared frozen empty value: the answer an absent, empty or
    # malformed field parses to — one object, stable identity. Defined
    # at the end of the class body because the constant's initializer
    # calls new, and initialize is defined above.
    EMPTY = new({})
    private_constant :EMPTY
  end
end
