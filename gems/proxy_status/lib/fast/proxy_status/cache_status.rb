# frozen_string_literal: true

module Fast
  # RFC 9211 Cache-Status: the HTTP response field that "indicates how
  # caches have handled that response and its corresponding request"
  # (§2). "Its value is a List. Each member of the List represents a
  # cache that has handled the request. The first member represents the
  # cache closest to the origin server, and the last member represents
  # the cache closest to the user (possibly including the user agent's
  # cache itself if it appends a value)" (§2) — the same List shape
  # Proxy-Status spells, so the class includes the shared
  # Fast::ProxyStatus::ListField engine and rides its one-walk/
  # two-policy parse, its positioning Scan, its frozen value object and
  # its append-yourself operation, answering the engine's hooks with
  # this field's member class (the Cache), empty value and label. Error,
  # ParseError, SerializeError, the Cache member class, the PARAMETERS
  # and FWD tables and EMPTY nest inside it.
  #
  # parse is the recipient's view and never raises on field content,
  # with the diagnostic leniency the List engine spells: a field whose
  # syntax is not a Structured Field Value, or whose List carries any
  # member that is not a String or Token, is the ENTIRE field ignored
  # (RFC 9651 §2.2 — RFC 9211 defines no other handling for members),
  # answering the shared frozen empty value, the same answer an absent
  # field gives; while parameters NEVER fail the field — unknown
  # parameters and known parameters of a type §2.1-§2.8 does not allow
  # are preserved in the Cache's data (#[], #params) and ignored
  # semantically (the typed readers answer nil). A String is one field
  # value; an Array is the field's lines, combined with ", "
  # (RFC 9651 §4.2) — a List has no last-wins, the members
  # concatenate. A wrong input type is a caller bug and raises
  # TypeError.
  #
  # parse! is strict truth: the List failure wrapped with its message
  # and byte offset, then the member constraint and §2.1-§2.8's
  # parameter constraints, the first offender in List order raised
  # positioned — the member's identifier offset, the parameter's VALUE
  # offset (just past the "="; the key's end for the valueless form).
  # valid? answers the same question with a boolean and never raises.
  #
  # The answer is a frozen value object: caches (the Cache members in
  # wire order), first/last naming §2's two ends, the eight typed
  # readers on each Cache (hit, fwd, fwd_status, ttl, stored,
  # collapsed, key, detail — nil when the parameter is absent or
  # wrong-typed) beside the raw #[] and #params, hit_and_fwd? surfacing
  # §2.1's exclusivity SHOULD, the canonical to_s ("" when nothing is
  # held), and class-checked canonical equality.
  #
  # to_s and construction are ALWAYS strict, in every family gem: a
  # sender never puts garbage on the wire — the identifier is a plain
  # String (emits quoted) or a Fast::SFV::Token (emits bare), the class
  # the wire-type tag; the eight parameters carry their sections' types;
  # and fwd is validated against §2.2's defined set on emit ONLY:
  # §2.2 defines the values, it does not MUST them on a recipient, and
  # a future registration must not break an old gem version — an
  # unregistered fwd Token parses and round-trips untouched.
  #
  # append is §2's append-yourself: "caches SHOULD preserve the
  # existing field value" — the received members in order, this cache's
  # member appended as the LAST (closest to the user), a new frozen
  # value.
  class CacheStatus
    # RFC 9651 value shapes aliased here, private to this class, so the
    # checks and the readers read them by the short name.
    Token = SFV::Token
    private_constant :Token

    # The Byte Sequence tag: a String tagged ASCII-8BIT IS the Byte
    # Sequence on the wire (RFC 9651 §3.3.5 — the encoding is the
    # wire-type tag), so the key parameter's constraint reads the same
    # fact, and a UTF-8 String would emit as a quoted sf-string.
    BINARY = Encoding::ASCII_8BIT
    private_constant :BINARY

    # The family root, one rescue for the whole gem: every
    # Fast::CacheStatus failure descends from Fast::ProxyStatus::Error,
    # so a caller can guard this class and its siblings with one
    # rescue. This class is never raised in its own right — every
    # failure here is either a parse defect or a serialization defect.
    # A wrong input type is a caller bug, not field content: it raises
    # plain TypeError and never this class.
    class Error < ProxyStatus::Error; end

    # A Cache-Status field this gem cannot read. Two shapes meet here:
    # the underlying RFC 9651 List failed to parse — the failure is
    # wrapped with its message and byte offset preserved — or, under the
    # strict parse, a member broke RFC 9211 §2's constraint (a member
    # that is not a String or Token) or a §2.1-§2.8 parameter broke its
    # section's type, and #offset is the byte position of the offending
    # member's identifier or parameter VALUE in the combined field value
    # (a member's, the member's first non-OWS byte; a parameter's, just
    # past the "=" — the key's end for the valueless form, the implicit
    # Boolean true). The lenient parse never raises it: a recipient that
    # cannot read the field ignores it entirely (RFC 9651 §2.2).
    class ParseError < Error
      attr_reader :offset

      def initialize(message, offset)
        super(message)
        @offset = offset
      end
    end

    # A value cannot go on the wire: the field under construction breaks
    # a bound RFC 9211 states — a member identifier that is not a plain
    # String or a Fast::SFV::Token (a String tagged ASCII-8BIT would
    # emit as a Byte Sequence), a §2.1-§2.8 parameter of a type its
    # section does not allow, an unknown parameter of a non-bare type, a
    # parameter key outside the Structured Fields key grammar, a fwd
    # Token outside §2.2's defined set, or members that are not Caches.
    # #offset is the byte position in the output built so far — 0,
    # because the check runs before anything is emitted; the whole emit
    # path raises this class and never TypeError: on emit the wrongness
    # is in the value being sent, which is field content, not a caller
    # protocol bug.
    class SerializeError < Error
      attr_reader :offset

      def initialize(message, offset)
        super(message)
        @offset = offset
      end
    end

    # §2.1-§2.8's eight parameters, key => the type its own section
    # states, worded as the sections word them — the wording both error
    # families carry. Frozen public data, its own lookup (a Hash IS its
    # registry's read); the table never gates a parse: an unknown
    # parameter parses, is preserved and round-trips (§4's registration
    # path — a future registration must not break an old gem version).
    PARAMETERS = {
      "hit" => "a Boolean",           # §2.1
      "fwd" => "a Token",             # §2.2
      "fwd-status" => "an Integer",   # §2.3
      "ttl" => "an Integer",          # §2.4
      "stored" => "a Boolean",        # §2.5
      "collapsed" => "a Boolean",     # §2.6
      "key" => "a String",            # §2.7
      "detail" => "a String or Token" # §2.8
    }.freeze

    # §2.2's fwd values, "from most specific to least" — the document
    # order the section spells them in. Frozen public data; the
    # emit-side enum check reads it, the parse side never does (§2.2
    # defines the values, it does not MUST them on a recipient).
    FWD = [
      "bypass",    # the cache was configured to not handle this request
      "method",    # the request method's semantics require forwarding
      "uri-miss",  # no stored response matched the request URI
      "vary-miss", # a stored URI match could not select a response
      "miss",      # no usable stored response (uri-miss/vary-miss indistinct)
      "request",   # a fresh response was selected, request semantics refused it
      "stale",     # a response was selected but it was stale
      "partial"    # a partial response lacked the requested ranges
    ].freeze

    # The shared List engine, as Proxy-Status includes it: the
    # class-level parse/parse!/valid?/append, the instance surface over
    # the members ivar, the construction boundary — all reading this
    # class's member class, empty value and label through the private
    # hooks below.
    include ProxyStatus::ListField

    # §2's member: one cache's entry in the List — "Each List member
    # identifies the cache that inserted it, and this identifier MUST
    # be a String or Token" (§2) — the substrate's Item IS the member
    # shape, so the subclass of the shared member base
    # (Fast::ProxyStatus::ListField::Member) inherits #value, #params,
    # the raw #[] reader and the canonical strict #to_s, and serializes
    # inside Fast::SFV.serialize_list unchanged, while §2.1-§2.8's
    # parameter rules, the eight typed readers, the exclusivity
    # surface and §2.2's emit-side enum check stay here, the field's
    # own table. A Cache never equals a Hop, whatever their value and
    # parameters — the class is the member's identity.
    class Cache < ProxyStatus::ListField::Member
      class << self
        # §2.1-§2.8's constraint for one parameter: true when +value+
        # carries the type the parameter's section allows, and always
        # true for an unknown key (§4's registration path — an unknown
        # parameter is preserved and ignored).
        def param_ok?(key, value)
          case key
          when "hit", "stored", "collapsed" then boolean_value?(value)
          when "fwd" then value.is_a?(Token)
          when "fwd-status", "ttl" then value.is_a?(Integer)
          when "key" then plain_string?(value)
          when "detail" then identifier_value?(value)
          else true
          end
        end

        # The type one of §2.1-§2.8's parameters allows, worded as its
        # section words it — nil for an unknown key. The wording the
        # ParseError and the SerializeError both carry.
        def param_rule(key)
          PARAMETERS[key]
        end

        # A Boolean parameter value — §2.1, §2.5 and §2.6's readers and
        # constraints share the shape: false is a value, never an
        # absence (§3's "collapsed=?0" example), so the check reads the
        # class, not the truth.
        def boolean_value?(value)
          value.is_a?(TrueClass) || value.is_a?(FalseClass)
        end

        private

        # The member base's error hook: Cache-Status's SerializeError
        # nests in the field class, not the member class.
        def serialize_error(message)
          SerializeError.new(message, 0)
        end

        # §2.7: "The value of 'key' is a String" — a plain String, not
        # a Token (a Token is a different wire type) and not a Byte
        # Sequence.
        def plain_string?(value)
          !value.is_a?(Token) && identifier_value?(value)
        end
      end

      # Strict construction — a sender never puts garbage on the wire.
      # +value+ is the cache's identifier: a plain String (emits
      # quoted) or a Fast::SFV::Token (emits bare) — the class is the
      # wire-type tag; a String tagged ASCII-8BIT is refused (it would
      # emit as a Byte Sequence). +params+ is a Hash of §2.1-§2.8
      # parameters under Structured Fields keys: the eight carry their
      # sections' types, any other parameter any bare Structured Fields
      # type. The value String and the params Hash are frozen IN PLACE
      # as part of the value object — pass copies if the buffers are
      # reused. Anything else raises SerializeError naming the
      # parameter and the type. The base's checks run first, then
      # §2.2's emit-side enum check below — the only field-specific
      # rule construction adds.
      def initialize(value, params = {})
        super
        check_fwd!
      end

      # §2.1: "The value of 'hit' is a Boolean that, when true,
      # indicates that the request was satisfied by the cache; that is,
      # it was not forwarded, and the response was obtained from the
      # cache." true, false, or nil — false is a value, never an
      # absence, exactly as §3's "collapsed=?0" example spells for its
      # own Boolean.
      def hit
        value = @params["hit"]
        Cache.boolean_value?(value) ? value : nil
      end

      # §2.2: "'fwd', when present, indicates that the request went
      # forward towards the origin; its value is a Token that indicates
      # why." The Token — a String that equals it spells it — or nil
      # when the parameter is absent or arrived as another type. Any
      # Token parses (§2.2 defines the values, it does not MUST them on
      # a recipient); construction validates the set.
      def fwd
        value = @params["fwd"]
        value.is_a?(Token) ? value : nil
      end

      # §2.3: "The value of 'fwd-status' is an Integer that indicates
      # which status code the next-hop server returned in response to
      # the forwarded request." The Integer or nil. The section's "If
      # fwd-status is not present but the fwd parameter is, it defaults
      # to the status code sent in the response" is a response-level
      # fact this field object never computes — the reader answers the
      # field only, the caller owns the response.
      def fwd_status
        value = @params["fwd-status"]
        value.is_a?(Integer) ? value : nil
      end

      # §2.4: "The value of 'ttl' is an Integer that indicates the
      # response's remaining freshness lifetime ... It may be negative,
      # to indicate staleness." The Integer — either sign, §3's
      # "ttl=-412" example — or nil.
      def ttl
        value = @params["ttl"]
        value.is_a?(Integer) ? value : nil
      end

      # §2.5: "The value of 'stored' is a Boolean that indicates whether
      # the cache stored the response ... a true value indicates that it
      # did." true, false, or nil.
      def stored
        value = @params["stored"]
        Cache.boolean_value?(value) ? value : nil
      end

      # §2.6: "The value of 'collapsed' is a Boolean that indicates
      # whether this request was collapsed together with one or more
      # other forward requests." true, false, or nil — §3's
      # "collapsed=?0" example: the collapse was attempted and failed,
      # a value, not an absence.
      def collapsed
        value = @params["collapsed"]
        Cache.boolean_value?(value) ? value : nil
      end

      # §2.7: "The value of 'key' is a String that conveys a
      # representation of the cache key used for the response." The
      # plain String — a Token is a different wire type — or nil.
      def key
        value = @params["key"]
        self.class.send(:plain_string?, value) ? value : nil
      end

      # §2.8: "The value of 'detail' is either a String or a Token that
      # allows implementations to convey additional information not
      # captured in other parameters" — §2's own example carries a
      # Token ("ExampleCache; hit; detail=MEMORY"). The String, the
      # Token, or nil.
      def detail
        value = @params["detail"]
        self.class.identifier_value?(value) ? value : nil
      end

      # §2.1's exclusivity SHOULD, surfaced: "'hit' and 'fwd' are
      # exclusive; only one of them should appear on each list member."
      # true exactly when both readers answer (false is a present hit),
      # and never a gate on a parse, a strict parse or an emit — a
      # SHOULD is sender advice, and the value object reports what the
      # sender sent.
      def hit_and_fwd?
        !hit.nil? && !fwd.nil?
      end

      private

      # §2.2's defined values, the emit-side-only check: a Token the
      # set does not carry cannot go on the wire from this gem, but it
      # PARSES and round-trips untouched — §2.2 defines the values, it
      # does not MUST them on a recipient, and a future registration
      # must not break an old gem version.
      def check_fwd!
        value = @params["fwd"]
        return unless value.is_a?(Token)
        return if FWD.include?(value)

        raise SerializeError.new("fwd: the value is a Token of the 2.2 set (#{FWD.join(', ')})", 0)
      end
    end

    class << self
      private

      # The engine's member-class hook: §2's member.
      def member_class
        Cache
      end

      # The engine's empty-value hook: the shared frozen empty value.
      def empty_value
        EMPTY
      end

      # The engine's field-label hook: the word the member errors
      # carry.
      def field_label
        "Cache-Status"
      end
    end

    # The held members: the frozen Array of Caches in wire order — §2's
    # order, the first member closest to the origin server, the last
    # closest to the user. The engine's members ivar, named.
    def caches
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
