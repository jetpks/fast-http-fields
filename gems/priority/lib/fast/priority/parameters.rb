# frozen_string_literal: true

module Fast
  module Priority
    # The RFC 9651 value shapes a Priority field holds: its members are
    # Fast::SFV Items and InnerLists. Aliased here — private to this
    # gem — so the filter, the strict check and the construction walk
    # read them by the short name.
    Item = SFV::Item
    InnerList = SFV::InnerList
    private_constant :Item, :InnerList

    # Items this gem builds carry no parameters, so they all share the
    # one frozen empty Hash — the parse path's own shape.
    EMPTY_PARAMS = {}.freeze
    private_constant :EMPTY_PARAMS

    # The empty unknown view, shared by every signal with no unknown
    # members.
    EMPTY_UNKNOWN = {}.freeze
    private_constant :EMPTY_UNKNOWN

    # The frozen value object behind every parse and every emit: the
    # EFFECTIVE members of a priority signal — "u" and "i" as bare
    # Items when they are present, the unknown members exactly as
    # parsed (§4.3's extension design) — with the readers a recipient
    # reads and the canonical wire form a sender sends.
    #
    # A member's ABSENCE is visible, never folded into a value:
    # #urgency and #incremental answer the §4 defaults (3 and false)
    # for an absent member while #to_s omits it, because RFC 9218
    # turns on the difference — §7: "Omitting a priority parameter is
    # a signal to use its default value", and §8: "The absence of a
    # priority parameter in an HTTP response indicates the server's
    # disinterest in changing the client-provided value".
    class Parameters
      # RFC 9218 §4.1: "The default is 3."
      DEFAULT_URGENCY = 3
      # The two keys this gem interprets (§4.1 and §4.2) — frozen at the
      # class level so the member walks allocate nothing per member.
      KNOWN_KEYS = %w[u i].freeze

      # The held members: "u"/"i" as bare Items when present, the
      # unknown members as parsed. Frozen and ordered — the parse's
      # order, a merge's order, or u-then-i-then-unknowns from the
      # keywords.
      attr_reader :members

      # Builds a signal from its three §4 parameters. Every keyword is
      # optional: an omitted (or nil) one means the member is ABSENT —
      # the reader still answers the §4 default and #to_s omits the
      # member. Strict, like every emit: urgency must be an Integer
      # 0..7 (§4.1), incremental a Boolean (§4.2), and unknown a Hash
      # of Fast::SFV Items and InnerLists under String keys other than
      # "u" and "i" — anything else raises SerializeError at
      # construction, so no unvalidated value ever reaches the wire.
      def initialize(urgency: nil, incremental: nil, unknown: nil)
        check_urgency(urgency)
        check_incremental(incremental)
        members = {}
        members["u"] = Item.new(urgency, EMPTY_PARAMS) unless urgency.nil?
        members["i"] = Item.new(incremental, EMPTY_PARAMS) unless incremental.nil?
        add_unknown(members, unknown)
        hold(members)
      end

      # RFC 9218 §4.1: the urgency (u) parameter — an Integer 0..7, in
      # descending order of priority. The default is 3, answered when
      # the member is absent.
      def urgency
        member_value("u", DEFAULT_URGENCY)
      end

      # RFC 9218 §4.2: the incremental (i) parameter — a Boolean: can
      # the response be processed incrementally. The default is false.
      def incremental
        member_value("i", false)
      end

      # The members this gem does not interpret — every key other than
      # "u" and "i", values as parsed, §4's unknown-parameter
      # passthrough. Frozen, empty for a signal with none.
      attr_reader :unknown

      # The canonical wire form: the RFC 9651 §4.1.2 Dictionary
      # serialization of the held members, "" when none are held — a
      # sender omits the field entirely, the same reason
      # Fast::SFV.serialize_dict answers nil for the empty Dictionary.
      # A member that cannot serialize raises Fast::Priority's own
      # SerializeError — the substrate's failure rewrapped with its
      # message and offset, so every failure this gem raises descends
      # from Fast::Priority::Error and one rescue catches them all.
      def to_s
        SFV.serialize_dict(@members) || ""
      rescue SFV::SerializeError => e
        raise SerializeError.new(e.message, e.offset)
      end

      # RFC 9218 §8: "No guidance is provided for merging priorities;
      # this is left as an implementation decision." This is the §8
      # example's rule, exposed as a helper: every parameter OTHER
      # holds wins (the example prefers the server-provided urgency),
      # every parameter other omits keeps self's, and the unknown
      # members union with other's winning collisions. Member order is
      # self's, then other's new keys. Answers a NEW frozen Parameters
      # with both inputs untouched — a caller with a different policy
      # writes their own merge over #members.
      def merge(other)
        raise TypeError, "a Fast::Priority::Parameters is required (got #{other.class})" unless other.is_a?(Parameters)

        Parameters.send(:from_members, @members.merge(other.members))
      end

      # Canonical-wire-form equality: two signals are the same when
      # they serialize the same, whatever objects hold the members.
      def ==(other)
        other.is_a?(Parameters) && to_s == other.to_s
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

      # The parse and merge paths hold their members already — SFV
      # Items and InnerLists the §4 filter or the §8 merge produced —
      # in a shape .new's keywords cannot express: a parsed "u=3;q=1"
      # keeps its parameters, and member order is the field's, not
      # u-then-i. Private to this gem's own paths.
      def self.from_members(members)
        parameters = allocate
        parameters.send(:hold, members)
        parameters
      end
      private_class_method :from_members

      private

      # The one place the held state is written, then frozen: the
      # members Hash as given, and the unknown view derived from it.
      def hold(members)
        @members = members.freeze
        @unknown = unknown_view(@members)
        freeze
      end

      # A §4 reader: the member's bare value when held, the RFC's
      # default when absent.
      def member_value(key, default)
        member = @members[key]
        member ? member.value : default
      end

      # The passthrough view: the members minus the two this gem
      # interprets. The empty view is shared — a signal with no
      # unknown members costs no Hash.
      def unknown_view(members)
        unknown = nil
        members.each do |key, value|
          next if KNOWN_KEYS.include?(key)

          unknown ||= {}
          unknown[key] = value
        end
        unknown ? unknown.freeze : EMPTY_UNKNOWN
      end

      # §4.1's bound at the boundary, before any member is built.
      def check_urgency(urgency)
        valid = case urgency
                when Integer then urgency.between?(0, 7)
                when nil then true
                else false
                end
        return if valid

        raise SerializeError.new("urgency is an Integer 0..7 (got #{shape(urgency)})", 0)
      end

      # §4.2's bound at the boundary, before any member is built.
      def check_incremental(incremental)
        case incremental
        when nil, true, false
          nil
        else
          raise SerializeError.new("incremental is a Boolean (got #{shape(incremental)})", 0)
        end
      end

      # The unknown members join after "u" and "i", in insertion
      # order, each validated as it is walked.
      def add_unknown(members, unknown)
        case unknown
        when nil
          nil
        when Hash
          unknown.each do |key, value|
            check_unknown_key(key)
            check_unknown_value(value)
            members[key] = value
          end
        else
          raise SerializeError.new("unknown members are a Hash (got #{shape(unknown)})", 0)
        end
      end

      # The two keys this gem interprets are set through the keywords;
      # every other member's key is a String, the wire form of a
      # Dictionary key.
      def check_unknown_key(key)
        valid = case key
                when String then !KNOWN_KEYS.include?(key)
                else false
                end
        return if valid

        raise SerializeError.new(
          "an unknown member's key is a String other than u and i, set through the keywords (got #{shape(key)})", 0
        )
      end

      # The wire shapes Fast::SFV serializes: an Item or an InnerList,
      # nothing else.
      def check_unknown_value(value)
        case value
        when Item, InnerList
          nil
        else
          raise SerializeError.new(
            "an unknown member's value is a Fast::SFV Item or InnerList (got #{shape(value)})", 0
          )
        end
      end

      # The class of a value an error message names, or a placeholder
      # when the value has none (a BasicObject descendant) — the
      # message never calls a method on the value it is rejecting.
      def shape(value)
        defined?(value.class) ? value.class : "a classless object"
      end
    end
  end
end
