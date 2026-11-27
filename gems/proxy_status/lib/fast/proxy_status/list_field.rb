# frozen_string_literal: true

module Fast
  class ProxyStatus
    # RFC 9651 value shapes aliased here, private to this gem, so the
    # checks and the walks read them by the short name.
    Item = SFV::Item
    Token = SFV::Token
    private_constant :Item, :Token

    # The Byte Sequence tag: a String tagged ASCII-8BIT IS the Byte
    # Sequence on the wire (RFC 9651 §3.3.5 — the encoding is the
    # wire-type tag), so the identifier constraint below reads the same
    # fact, and a UTF-8 String would emit as a quoted sf-string.
    BINARY = Encoding::ASCII_8BIT
    private_constant :BINARY

    # The shared engine of the gem's two List fields. Proxy-Status
    # (RFC 9209 §2) and Cache-Status (RFC 9211 §2) are both RFC 9651
    # Lists of parameterized Items whose members identify the
    # intermediary or cache that inserted them, and both RFCs state the
    # same member constraint (RFC 9209 §2: "this identifier MUST be a
    # String or Token"; RFC 9211 §2: "this identifier MUST be a String
    # or Token"), so the List machinery lives here once: the
    # one-walk/two-policy parse, the positioning Scan, the frozen value
    # object over the members, the append-yourself operation and the
    # generic member construction boundary. A field class includes this
    # module and answers three private class hooks — member_class,
    # empty_value and field_label — while its member class subclasses
    # ListField::Member with its own parameter table and typed readers.
    # The RFC 9213 field is a Dictionary and does not include this
    # module: its members are key-value and its leniency is
    # per-directive, not whole-field.
    #
    # The engine raises the FIELD's errors: the class-level machinery
    # resolves them as self::ParseError and the instance-level as
    # self.class::SerializeError, because each field's error hierarchy
    # nests in the field class (and every one of them descends from
    # Fast::ProxyStatus::Error, so a caller can guard the whole gem
    # with one rescue). The field's empty value is read through the
    # empty_value hook for the same reason: a private constant of one
    # field class is unreachable from another's scope, and a bare EMPTY
    # in this module would resolve to the wrong field's value.
    module ListField
      # The class-level engine, extended into the field class by the
      # include below: the two parses, the boolean mirror, the
      # append-yourself class form, and the private one-walk/two-policy
      # machinery they share.
      module ClassMethods
        # RFC 9651 §2.2, the recipient semantics — never raises on field
        # content. A field whose syntax is not a Structured Field Value,
        # or whose List carries ANY member that is not a String or Token,
        # is the ENTIRE field ignored ("When field-specific constraints
        # are violated, the entire field is also ignored, unless the
        # field definition defines other handling requirements" — the
        # field's own RFC defines no other handling for members): the
        # shared frozen empty value, the same answer an absent field
        # gives. Parameters NEVER fail the field: an unknown parameter
        # is preserved in the member's data and ignored semantically,
        # and a known parameter of a type the field's own sections do
        # not allow is likewise preserved and ignored by the typed
        # readers — the lenient parse is THIS walk with the parameter
        # checks not applied, never the strict walk rescued, so a
        # parameter violation can never drop the field while a member
        # violation must. "" is the valid empty List (RFC 9651 §4.2.1)
        # and parses to a fresh empty value. A String is one field
        # value; an Array is the field's lines, combined with ", "
        # (§4.2) — a List has no last-wins, the members concatenate.
        # A wrong input type is a caller bug and raises TypeError.
        def parse(input)
          walk(input, false)
        rescue self::ParseError
          empty_value
        end

        # Strict truth. The RFC 9651 List failure is wrapped with its
        # message and byte offset preserved; then the constraints, the
        # FIRST offender in List order raised positioned: the member
        # constraint (a member that is not a String or Token) at the
        # member's identifier — its first non-OWS byte in the combined
        # field value — and the field's own parameter constraints at the
        # parameter's VALUE, just past the "=" (the key's end for the
        # valueless form, the implicit Boolean true), the message naming
        # the parameter and the type the field's section states.
        # Unknown parameters are valid and preserved on the strict path.
        # TypeError for a wrong input type, as parse.
        def parse!(input)
          walk(input, true)
        end

        # The boolean mirror: true exactly when parse! returns — false
        # for malformed content, member violations, wrong-typed
        # parameters and a wrong input type alike (a caller bug is not
        # field content either). The empty value is true.
        def valid?(input)
          walk(input, true)
          true
        rescue TypeError, self::ParseError
          false
        end

        # The append-yourself operation, the class form. +input+ is the
        # field as received — a String, an Array of field lines, an
        # existing value reused as held, or nil for a response bearing
        # none — parsed leniently (a malformed upstream field is treated
        # as absent: the sender starts a fresh list rather than failing
        # the response); this sender's +member+ is appended as the LAST
        # member (the field's RFC: closest to the user) with the
        # received members preserved in order. Answers a NEW frozen
        # value whose to_s re-emits the whole list canonically.
        # TypeError for a wrong +input+ type (a caller bug);
        # SerializeError for a wrong member or parameter (field
        # content, the construction boundary).
        def append(input, member, params = {})
          held_value(input).append(member, params)
        end

        private

        # The one walk behind parse and parse!: the RFC 9651 List parse,
        # then the member constraint on every member in List order and —
        # only when +strict+ — the field's parameter constraints, the
        # first offender raised positioned. The lenient parse is THIS
        # walk with the parameter checks not applied, never the strict
        # walk rescued: a parameter violation must not drop the field
        # while a member violation must (RFC 9651 §2.2), and the shared
        # constraint predicates and Scan keep the two policies'
        # semantics and offsets from drifting. The underlying List
        # failure is wrapped with its message and offset.
        def walk(input, strict)
          members = SFV.parse_list(input)
          from_members(members_from_items(members, input, strict))
        rescue SFV::ParseError => e
          raise self::ParseError.new(e.message, e.offset)
        end

        # The member walk over a parsed List: the member constraint on
        # every member, then the field's parameter checks (strict only),
        # the first offender in List order raising positioned — a
        # member's params are checked before the NEXT member, so
        # "good; error=5, 5" raises at the parameter. A manual position
        # counter: the member index the region scan reads.
        def members_from_items(members, input, strict)
          index = 0
          while index < members.size
            member = members[index]
            fail_member!(input, index, member) unless member_class.member_ok?(member)
            check_params!(member, input, index) if strict
            index += 1
          end
          members.map { |member| member_class.from_item(member) }
        end

        # The byte offsets the strict path positions with, read from
        # the substrate's region scan — consulted only where an error
        # needs an offset, so the clean path pays nothing for
        # positioning. The scan is the substrate's own §4.2 walk (RFC
        # 9651 display strings, parameters on every member form), so
        # the offset survives the members a private walk would desync
        # on.
        def member_value_offset(input, index)
          SFV.regions_list(input).members[index].value_start
        end

        # The member +index+'s +key+ parameter VALUE offset: the LAST
        # occurrence of the key in the member's parameter group — the
        # one the last-wins parameter Hash kept — just past its "=", or
        # the key's end for the valueless form (the implicit Boolean
        # true, where a value would be written).
        def param_value_offset(input, index, key)
          regions = SFV.regions_list(input)
          offset = nil
          regions.members[index].params.each do |param|
            param_key = regions.combined.byteslice(param.key_start, param.key_end - param.key_start)
            offset = param.value_start if param_key == key
          end
          offset
        end

        # The member constraint, positioned at the member's identifier.
        def fail_member!(input, index, member)
          offset = member_value_offset(input, index)
          raise self::ParseError.new("a #{field_label} member is a String or Token (got #{shown(member)})", offset)
        end

        # The field's parameter constraints over one member, in the
        # parameters' wire order: the first offender raises positioned
        # at its VALUE. Unknown parameters are skipped — the field's own
        # "unrecognised parameters MUST be ignored" rule — and
        # preserved.
        def check_params!(member, input, index)
          member.params.each do |key, value|
            rule = member_class.param_rule(key)
            next if rule.nil? || member_class.param_ok?(key, value)

            offset = param_value_offset(input, index, key)
            raise self::ParseError.new("#{key}: the value is #{rule} (got #{value})", offset)
          end
        end

        # What a member error shows of the offender: the bare value when
        # it is an Item (a wrong type), the member's class when it is not
        # an Item at all — an inner list.
        def shown(member)
          member.is_a?(Item) ? member.value : member.class
        end

        # A field argument as received, the value form: nil for the
        # absent field (the empty value — a fresh list), an existing
        # value reused as held, a String or Array of lines parsed
        # leniently (a malformed field treated as absent). TypeError for
        # anything else.
        def held_value(input)
          return empty_value if input.nil?
          return input if input.is_a?(self)

          parse(input)
        end

        # The value object behind members that already passed the
        # checks: the members held as given, no re-validation (the parse
        # path and append build members at their own boundaries).
        def from_members(members)
          field = allocate
          field.send(:hold, members)
          field
        end
      end

      # Rides the include: the class-level engine above becomes the
      # field class's class methods.
      def self.included(base)
        base.extend ClassMethods
      end

      # The first member of the List — the field's RFC: the member
      # closest to the origin server. nil when nothing is held.
      def first
        @members.first
      end

      # The last member — the field's RFC: the member closest to the
      # user. nil when nothing is held.
      def last
        @members.last
      end

      # How many members the field holds.
      def size
        @members.size
      end

      # No members held — an absent field, or one treated as absent.
      def empty?
        @members.empty?
      end

      # Yields each member in wire order.
      def each(&block)
        @members.each(&block)
      end

      # The member at +index+ — Array semantics (negative indices, nil
      # beyond the ends).
      def [](index)
        @members[index]
      end

      # The append-yourself operation, the instance form: the received
      # members preserved in order, this sender's member appended as the
      # LAST (the field's RFC: closest to the user). Answers a NEW
      # frozen value; self is never mutated, and to_s re-emits the whole
      # list canonically (non-canonical spacing normalizes through the
      # round-trip). +member+ is the identifier (a plain String emits
      # quoted, a Token bare), +params+ the parameter Hash;
      # SerializeError for a wrong member or parameter (the construction
      # boundary).
      def append(member, params = {})
        members = @members.dup
        members << self.class.send(:member_class).new(member, params)
        self.class.send(:from_members, members)
      end

      # The canonical wire form: the RFC 9651 §4.1.1 List serialization
      # of the held members, "" when none are held (a sender omits the
      # field entirely — the same reason Fast::SFV.serialize_list
      # answers nil for the empty List). Never raises: construction
      # validated every member, and a parsed value re-emits its
      # canonical form.
      def to_s
        SFV.serialize_list(@members) || ""
      end

      # Canonical-wire-form equality WITHIN the field class: two fields
      # are the same when they serialize the same.
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

      # Strict construction — a sender never puts garbage on the wire.
      # +members+ is an Array of the field's member objects, each
      # validated at its own construction (the member class's new is the
      # boundary); the Array freezes IN PLACE. The empty Array builds
      # the empty value: a sender omits the field entirely.
      def initialize(members)
        check_members!(members)
        hold(members)
      end

      private

      # The construction boundary: an Array of the field's members, each
      # already validated at its own construction.
      def check_members!(members)
        klass = self.class.send(:member_class)
        unless members.is_a?(Array)
          raise self.class::SerializeError.new("members are an Array of #{klass} (got #{members.class})", 0)
        end

        members.each { |member| check_member!(member) }
      end

      # One member's boundary: a member of the field's member class —
      # its own construction was its validation.
      def check_member!(member)
        klass = self.class.send(:member_class)
        return if member.is_a?(klass)

        raise self.class::SerializeError.new("a member is a #{klass} (got #{member.class})", 0)
      end

      # The one place the held state is written, then frozen: the
      # members Array (frozen already on the parse path, frozen in place
      # by a construction). Each field's public reader names it —
      # ProxyStatus #hops, CacheStatus #caches.
      def hold(members)
        @members = members.freeze
        freeze
      end

      # The member base of the two List fields: the generic half of the
      # member value object, everything the two RFCs state identically.
      # The subclass — Fast::ProxyStatus::Hop,
      # Fast::CacheStatus::Cache — declares its own parameter table
      # (param_rule/param_ok?, the field's own sections) and its typed
      # readers, and answers the FIELD's SerializeError through the
      # private serialize_error hook, because the error hierarchy nests
      # in the field class, not in the member class. The base is an
      # Fast::SFV::Item: #value, #params and the canonical strict #to_s
      # are inherited and the member serializes inside
      # Fast::SFV.serialize_list unchanged, while the base adds the raw
      # #[] reader, the identifier and parameter construction boundary,
      # and class-checked canonical equality (a Hop never equals a
      # Cache, whatever their value and parameters — the class is the
      # member's identity).
      class Member < Item
        # A 256-entry byte class: true for every byte of +spec+ — the
        # byte-table shape the family's scanners walk with.
        def self.byte_class(spec)
          table = Array.new(256, false)
          spec.each_byte { |byte| table[byte] = true }
          table.freeze
        end
        private_class_method :byte_class

        # A Structured Fields key's first byte: lcalpha or "*" (RFC 9651
        # §4.2.3.3 step 1) — the grammar a parameter key must spell.
        KEY_FIRST = byte_class("abcdefghijklmnopqrstuvwxyz*")
        # A key's continuation: lcalpha, DIGIT, "_", "-", "." or "*"
        # (§4.2.3.3) — the class the construction's key walk and the
        # Scan's key walk read (the first byte is a member of it).
        KEY_BODY = byte_class("abcdefghijklmnopqrstuvwxyz0123456789_-.*")

        class << self
          # The member constraint both List fields state: every member
          # an Item whose value is a String or Token. A violation is the
          # ENTIRE field ignored under the lenient parse (RFC 9651 §2.2
          # — neither field defines other handling for members) and a
          # positioned ParseError under the strict one.
          def member_ok?(member)
            member.is_a?(Item) && identifier_value?(member.value)
          end

          # The identifier's constraint: a Token, or a plain String —
          # the class is the wire-type tag (a plain String emits
          # quoted, a Token bare, and the content never decides which).
          # A String tagged ASCII-8BIT is a Byte Sequence on the wire,
          # not a String, so it fails here and the construction refuses
          # it.
          def identifier_value?(value)
            value.is_a?(Token) || (value.is_a?(String) && value.encoding != BINARY)
          end

          # A bare Structured Fields type (RFC 9651 §3.3.1) — the value
          # set an unknown parameter accepts at construction: Integer,
          # Float, String (a Token is one, a binary-tagged one is a Byte
          # Sequence), Boolean, Date or DisplayString. A Symbol or nil
          # is wrong-typed input and never reaches the wire.
          def bare_type?(value)
            case value
            when Integer, Float, String, true, false, SFV::Date, SFV::DisplayString then true
            else false
            end
          end

          # The parse-path constructor: no re-validation, the value and
          # params held as parsed — the parser already guaranteed the
          # wire grammar, and a wrong-typed parameter is diagnostic DATA
          # the lenient parse preserves, never a construction failure.
          def from_item(item)
            member = allocate
            member.send(:hold, item.value, item.params)
            member
          end
        end

        # Strict construction — a sender never puts garbage on the wire.
        # +value+ is the member's identifier: a plain String (emits
        # quoted) or a Fast::SFV::Token (emits bare) — the class is the
        # wire-type tag; a String tagged ASCII-8BIT is refused (it would
        # emit as a Byte Sequence). +params+ is a Hash of the field's
        # parameters under Structured Fields keys: the ones the field's
        # own sections define carry their sections' types, any other
        # parameter any bare Structured Fields type. The value String
        # and the params Hash are frozen IN PLACE as part of the value
        # object — pass copies if the buffers are reused. Anything else
        # raises SerializeError naming the parameter and the type;
        # byte-level String validity stays the serializer's own check
        # at #to_s, so a pathological hand-built value fails there — a
        # parsed value can never reach it.
        def initialize(value, params = {})
          check_value!(value)
          check_params!(params)
          value.freeze
          super(value, params)
        end

        # Any parameter's value, whatever type it arrived as — the
        # diagnostic leniency's raw view: unknown parameters and
        # wrong-typed ones are preserved in the data (#[], #params) and
        # ignored by the typed readers.
        def [](key)
          @params[key]
        end

        # Canonical-wire-form equality WITHIN the member class: a
        # member never equals a plain Item, or a member of the other
        # field's class, whatever their value and parameters — the
        # class is the member's identity.
        def ==(other)
          other.instance_of?(self.class) && to_s == other.to_s
        end
        alias eql? ==

        # Consistent with eql? — the canonical form's hash.
        def hash
          to_s.hash
        end

        def inspect
          "#<#{self.class.name} #{self}>"
        end

        private

        # The one place the held state is written, then frozen: the
        # parse path's already-frozen value and params, as parsed.
        def hold(value, params)
          @value = value
          @params = params
          freeze
        end

        # The identifier constraint at the boundary.
        def check_value!(value)
          return if self.class.identifier_value?(value)

          raise self.class.send(:serialize_error, "a member identifier is a String or a Token (got #{value.inspect})")
        end

        # The params boundary: a Hash of Structured Fields keys, each
        # value the type its key's section allows (any bare type for an
        # unknown key), frozen IN PLACE.
        def check_params!(params)
          raise self.class.send(:serialize_error, "params are a Hash (got #{params.class})") unless params.is_a?(Hash)

          params.each do |key, value|
            check_key!(key)
            check_param!(key, value)
          end
          params.freeze
        end

        # The parameter key grammar, RFC 9651 §4.2.3.3 read from the
        # value side: a String whose first byte is lcalpha or "*" and
        # whose bytes continue in lcalpha, DIGIT, "_", "-", "." or "*".
        def check_key!(key)
          return if valid_key?(key)

          raise self.class.send(:serialize_error, "#{key.inspect} is not a Structured Fields key")
        end

        # The walk behind check_key! — manual and allocation-free, the
        # shape the substrate's own key parse uses.
        def valid_key?(key)
          return false unless key.is_a?(String)

          size = key.bytesize
          return false if size.zero? || !KEY_FIRST[key.getbyte(0)]

          index = 1
          while index < size
            return false unless KEY_BODY[key.getbyte(index)]

            index += 1
          end
          true
        end

        # One parameter's value at the boundary: a key the field's own
        # sections define carries its section's type, any other key any
        # bare Structured Fields type.
        def check_param!(key, value)
          rule = self.class.param_rule(key)
          if rule
            return if self.class.param_ok?(key, value)

            raise self.class.send(:serialize_error, "#{key}: the value is #{rule} (got #{value.inspect})")
          end
          return if self.class.bare_type?(value)

          raise self.class.send(:serialize_error,
                                "#{key}: the value is a bare Structured Fields type (got #{value.inspect})")
        end
      end
    end
  end
end
