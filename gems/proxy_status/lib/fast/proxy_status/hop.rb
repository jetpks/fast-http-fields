# frozen_string_literal: true

module Fast
  class ProxyStatus
    # RFC 9209 §2's member: one intermediary's entry in the List — the
    # substrate's Item IS the member shape ("Each member of the List
    # identifies the intermediary that inserted the value and MUST have
    # a type of either String or Token"; parameters "convey additional
    # information about that intermediary's handling of the response and
    # its associated request; see Section 2.1"), so the subclass of the
    # shared member base (Fast::ProxyStatus::ListField::Member) inherits
    # #value, #params, the raw #[] reader and the canonical strict #to_s,
    # and serializes inside Fast::SFV.serialize_list unchanged — while
    # §2.1's five parameter rules, the five typed readers and §2.1.3's
    # Token-or-Byte-Sequence rule stay here, the field's own table. The
    # member constraint, the key grammar and the generic construction
    # boundary are the base's (RFC 9211 §2, Cache-Status's member,
    # spells the identical identifier constraint); the shared
    # constraint surface the parse walk and the construction read is
    # one surface across both List fields, so the lenient parse, the
    # strict parse and the emit cannot drift.
    class Hop < ListField::Member
      # §2.1's five parameters, key => the type its own section states,
      # worded as the sections word them — the wording both error
      # families carry. An unknown key answers nil from param_rule and
      # true from param_ok?: "Unrecognised parameters MUST be ignored"
      # (§2.1) — and accepts any bare Structured Fields type at
      # construction.
      PARAM_RULES = {
        "error" => "a Token",                          # §2.1.1
        "next-hop" => "a String or Token",             # §2.1.2
        "next-protocol" => "a Token or Byte Sequence", # §2.1.3
        "received-status" => "an Integer",             # §2.1.4
        "details" => "a String"                        # §2.1.5
      }.freeze
      private_constant :PARAM_RULES

      class << self
        # §2.1's constraint for one parameter: true when +value+ carries
        # the type the parameter's section allows, and always true for
        # an unknown key ("Unrecognised parameters MUST be ignored",
        # §2.1).
        def param_ok?(key, value)
          case key
          when "error" then token_value?(value)
          when "next-hop" then identifier_value?(value)
          when "next-protocol" then byte_value?(value)
          when "received-status" then integer_value?(value)
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

        # The identifier constraint under the name this field's public
        # surface froze — the base's identifier_value? answers the same
        # String-or-Token rule for the shared machinery.
        def hop_value?(value)
          identifier_value?(value)
        end

        # §2.1.3: "The value MUST be either a Token or Byte Sequence" —
        # a Token, or a String tagged ASCII-8BIT (the Byte Sequence
        # tag).
        def byte_value?(value)
          case value
          when Token
            true
          when String
            value.encoding == BINARY
          else
            false
          end
        end

        # §2.1.1's shape, as a never-dispatch predicate: a Token.
        def token_value?(value)
          case value
          when Token
            true
          else
            false
          end
        end

        # §2.1.4's shape, as a never-dispatch predicate: an Integer.
        def integer_value?(value)
          case value
          when Integer
            true
          else
            false
          end
        end

        private

        # The member base's error hook: §2.1's SerializeError nests in
        # the field class, not the member class.
        def serialize_error(message)
          SerializeError.new(message, 0)
        end

        # §2.1.5: "The details parameter's value is a String" — a plain
        # String, not a Token (a Token is a different wire type) and not
        # a Byte Sequence.
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
    end
  end
end
