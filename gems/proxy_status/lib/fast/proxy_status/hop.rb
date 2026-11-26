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
    # wire-type tag), so the identifier constraint and the
    # next-protocol constraint read the same fact, and a UTF-8 String
    # would emit as a quoted sf-string.
    BINARY = Encoding::ASCII_8BIT
    private_constant :BINARY

    # RFC 9209 §2's member: one intermediary's entry in the List — the
    # substrate's Item IS the member shape ("Each member of the List
    # identifies the intermediary that inserted the value and MUST have
    # a type of either String or Token"; parameters "convey additional
    # information about that intermediary's handling of the response and
    # its associated request; see Section 2.1"), so the subclass inherits
    # #value, #params and the canonical strict #to_s and serializes
    # inside Fast::SFV.serialize_list unchanged, and adds the raw #[]
    # reader, the five §2.1 typed readers, the strict construction
    # boundary and class-checked canonical equality.
    #
    # The class also carries the constraint surface the parse walk and
    # the construction share — member_ok?, hop_value?, param_ok?,
    # param_rule, byte_value?, bare_type? — so the lenient parse, the
    # strict parse and the emit read ONE set of rules and their
    # semantics cannot drift.
    class Hop < Item
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
      # (§4.2.3.3) — the class the Scan's key walk reads too (the first
      # byte is a member of it).
      KEY_BODY = byte_class("abcdefghijklmnopqrstuvwxyz0123456789_-.*")

      # §2.1's five parameters, key => the type its own section states,
      # worded as the sections word them — the wording both error
      # families carry. An unknown key answers nil from param_rule and
      # true from param_ok?: "Unrecognised parameters MUST be ignored"
      # (§2.1) — and accepts any bare Structured Fields type at
      # construction.
      PARAM_RULES = {
        "error" => "a Token",                       # §2.1.1
        "next-hop" => "a String or Token",          # §2.1.2
        "next-protocol" => "a Token or Byte Sequence", # §2.1.3
        "received-status" => "an Integer",          # §2.1.4
        "details" => "a String"                     # §2.1.5
      }.freeze
      private_constant :PARAM_RULES

      class << self
        # §2's member constraint: every member an Item whose value is a
        # String or Token. A violation is the ENTIRE field ignored under
        # the lenient parse (RFC 9651 §2.2 — RFC 9209 defines no other
        # handling for members) and a positioned ParseError under the
        # strict one.
        def member_ok?(member)
          member.is_a?(Item) && hop_value?(member.value)
        end

        # The identifier's constraint: a Token, or a plain String — the
        # class is the wire-type tag (a plain String emits quoted, a
        # Token bare, and the content never decides which). A String
        # tagged ASCII-8BIT is a Byte Sequence on the wire, not a
        # String, so it fails here and the construction refuses it.
        def hop_value?(value)
          value.is_a?(Token) || (value.is_a?(String) && value.encoding != BINARY)
        end

        # §2.1's constraint for one parameter: true when +value+ carries
        # the type the parameter's section allows, and always true for
        # an unknown key ("Unrecognised parameters MUST be ignored",
        # §2.1).
        def param_ok?(key, value)
          case key
          when "error" then value.is_a?(Token)
          when "next-hop" then hop_value?(value)
          when "next-protocol" then byte_value?(value)
          when "received-status" then value.is_a?(Integer)
          when "details" then plain_string?(value)
          else true
          end
        end

        # The type one of §2.1's parameters allows, worded as its
        # section words it — nil for an unknown key. The wording the
        # ParseError and the SerializeError both carry.
        def param_rule(key)
          PARAM_RULES[key]
        end

        # §2.1.3: "The value MUST be either a Token or Byte Sequence" —
        # a Token, or a String tagged ASCII-8BIT (the Byte Sequence
        # tag).
        def byte_value?(value)
          value.is_a?(Token) || (value.is_a?(String) && value.encoding == BINARY)
        end

        # A bare Structured Fields type (RFC 9651 §3.3.1) — the value
        # set an unknown parameter accepts at construction: Integer,
        # Float, String (a Token is one, a binary-tagged one is a Byte
        # Sequence), Boolean, Date or DisplayString. A Symbol or nil is
        # wrong-typed input and never reaches the wire.
        def bare_type?(value)
          case value
          when Integer, Float, String, true, false, SFV::Date, SFV::DisplayString then true
          else false
          end
        end

        # The parse-path constructor: no re-validation, the value and
        # params held as parsed — the parser already guaranteed the wire
        # grammar, and a wrong-typed §2.1 parameter is diagnostic DATA
        # the lenient parse preserves, never a construction failure.
        def from_item(item)
          hop = allocate
          hop.send(:hold, item.value, item.params)
          hop
        end

        private

        # §2.1.5: "The details parameter's value is a String" — a plain
        # String, not a Token (a Token is a different wire type) and not
        # a Byte Sequence.
        def plain_string?(value)
          !value.is_a?(Token) && hop_value?(value)
        end
      end

      # Strict construction — a sender never puts garbage on the wire.
      # +value+ is the intermediary's identifier: a plain String (emits
      # quoted) or a Fast::SFV::Token (emits bare) — the class is the
      # wire-type tag; a String tagged ASCII-8BIT is refused (it would
      # emit as a Byte Sequence). +params+ is a Hash of §2.1 parameters
      # under Structured Fields keys: the five carry their sections'
      # types, any other parameter any bare Structured Fields type. The
      # value String and the params Hash are frozen IN PLACE as part of
      # the value object — pass copies if the buffers are reused.
      # Anything else raises SerializeError naming the parameter and
      # the type; byte-level String validity stays the serializer's own
      # check at #to_s, so a pathological hand-built value fails there —
      # a parsed value can never reach it.
      def initialize(value, params = {})
        check_value!(value)
        check_params!(params)
        value.freeze
        super(value, params)
      end

      # Any parameter's value, whatever type it arrived as — the
      # diagnostic leniency's raw view: unknown parameters and
      # wrong-typed §2.1 ones are preserved in the data (#[], #params)
      # and ignored by the typed readers below.
      def [](key)
        @params[key]
      end

      # §2.1.1: "The error parameter's value is a Token that is a proxy
      # error type." The Token — a String that equals it spells it — or
      # nil when the parameter is absent or arrived as another type.
      def error
        value = @params["error"]
        value.is_a?(Token) ? value : nil
      end

      # §2.1.2: "The next-hop parameter's value is a String or Token
      # that identifies the intermediary or origin server selected."
      # The String or Token, or nil for another type.
      def next_hop
        value = @params["next-hop"]
        Hop.hop_value?(value) ? value : nil
      end

      # §2.1.3: "The value MUST be either a Token or Byte Sequence
      # representing a TLS ALPN Protocol ID." The Token or the binary
      # String, or nil for another type. The section's "If the protocol
      # identifier is able to be expressed as a Token using ASCII
      # encoding, that form MUST be used" is sender advice on which
      # form to emit, never a recipient's rejection of the Byte
      # Sequence form.
      def next_protocol
        value = @params["next-protocol"]
        Hop.byte_value?(value) ? value : nil
      end

      # §2.1.4: "The value MUST be an Integer." The Integer — no range
      # constraint: the section states the type only — or nil.
      def received_status
        value = @params["received-status"]
        value.is_a?(Integer) ? value : nil
      end

      # §2.1.5: "The details parameter's value is a String containing
      # additional information not captured anywhere else." The plain
      # String — a Token is a different wire type — or nil.
      def details
        value = @params["details"]
        self.class.send(:plain_string?, value) ? value : nil
      end

      # Canonical-wire-form equality WITHIN the Hop class: a Hop never
      # equals a plain Item, whatever their value and parameters — the
      # class is the member's identity.
      def ==(other)
        other.instance_of?(Hop) && to_s == other.to_s
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
        return if Hop.hop_value?(value)

        raise SerializeError.new("a hop identifier is a String or a Token (got #{value.inspect})", 0)
      end

      # The params boundary: a Hash of Structured Fields keys with the
      # §2.1 types, frozen IN PLACE.
      def check_params!(params)
        raise SerializeError.new("params are a Hash (got #{params.class})", 0) unless params.is_a?(Hash)

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

        raise SerializeError.new("#{key.inspect} is not a Structured Fields key", 0)
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

      # One parameter's value at the boundary: a §2.1 key carries its
      # section's type, any other key any bare Structured Fields type.
      def check_param!(key, value)
        rule = Hop.param_rule(key)
        if rule
          return if Hop.param_ok?(key, value)

          raise SerializeError.new("#{key}: the value is #{rule} (got #{value.inspect})", 0)
        end
        return if Hop.bare_type?(value)

        raise SerializeError.new("#{key}: the value is a bare Structured Fields type (got #{value.inspect})", 0)
      end
    end
  end
end
