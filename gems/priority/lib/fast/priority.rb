# frozen_string_literal: true

# The substrate: RFC 9218's priority parameters ride in an RFC 9651
# Dictionary, so this gem is a fast-sfv consumer, never a parser of
# its own.
require "fast/sfv"

require_relative "priority/version"
require_relative "priority/errors"
require_relative "priority/parameters"
require_relative "priority/field"
require_relative "priority/h2"
require_relative "priority/h3"

module Fast
  # RFC 9218 Extensible Priorities: the Priority HTTP header field and
  # the HTTP/2/HTTP/3 PRIORITY_UPDATE frame payloads.
  #
  # The Priority field is a Dictionary (§5: "The Priority HTTP header
  # field is a Dictionary that carries priority parameters"), so
  # Fast::Priority.parse hands the field value to Fast::SFV.parse_dict
  # and then applies §4's recipient semantics on what parsed.
  #
  # parse is the recipient's view and never raises on field content: a
  # malformed or absent field answers the §4 defaults (urgency 3,
  # incremental false, no member held), and a parsed Dictionary is
  # filtered member by member — §4: "unknown priority parameters,
  # priority parameters with out-of-range values, or values of
  # unexpected types MUST be ignored" — so an out-of-range or
  # wrong-typed "u" or "i" is dropped, unknown members pass through as
  # parsed, and what survives is held. A String is one field value; an
  # Array is the field's lines, combined with ", " (RFC 9651 §4.2). A
  # wrong input type is a caller bug and raises TypeError.
  #
  # parse! is strict truth: the Dictionary failure wrapped with its
  # message and byte offset, then §4 inverted on the effective
  # (last-wins) members — a held "u" that is not an Integer 0..7 (§4.1)
  # or a held "i" that is not a Boolean (§4.2) raises a ParseError
  # pointing at the member's value. valid? answers the same question
  # with a boolean and never raises.
  #
  # The answer is a frozen Fast::Priority::Parameters: urgency,
  # incremental, the unknown members, the held members, the canonical
  # to_s ("" when nothing is held — a sender omits the field), the §8
  # merge helper, and canonical-wire-form equality. A member's ABSENCE
  # is visible, not folded into a default: §7 ("Omitting a priority
  # parameter is a signal to use its default value") and §8 ("The
  # absence of a priority parameter in an HTTP response indicates the
  # server's disinterest in changing the client-provided value") both
  # turn on the difference. to_s and the frame encoders are ALWAYS
  # strict, in every family gem: a sender never puts garbage on the
  # wire.
  #
  # Fast::Priority::H2 and Fast::Priority::H3 are the PRIORITY_UPDATE
  # frame payload codecs (§7.1 and §7.2): byte-exact encode and decode
  # of the payload after the frame header — the h2 Reserved(1)+
  # Prioritized Stream ID(31) word, the h3 QUIC variable-length
  # Prioritized Element ID — plus the Priority Field Value. A field
  # value that fails the Dictionary parse is surfaced on the result's
  # #error ("Failure to parse the Priority Field Value MAY be treated
  # as a connection error" — the caller owns that MAY); a
  # parsed-but-ignored member is not a failure. The frame headers, the
  # stream-state rules and every SETTINGS decision are the
  # transport's: this gem keeps no connection or stream state.
  module Priority
  end
end
