# frozen_string_literal: true

# The substrate: RFC 9209's Proxy-Status is an RFC 9651 List, so this
# gem is a fast-sfv consumer, never a parser of its own.
require "fast/sfv"

require_relative "proxy_status/version"
require_relative "proxy_status/errors"
require_relative "proxy_status/registry"
require_relative "proxy_status/hop"
require_relative "proxy_status/status"

module Fast
  # RFC 9209 Proxy-Status: the HTTP response field that conveys how
  # intermediaries handled a response. "Its value is a List (see
  # Section 3.1 of [STRUCTURED-FIELDS]). Each member of the List
  # represents an intermediary that has handled the response. The first
  # member represents the intermediary closest to the origin server, and
  # the last member represents the intermediary closest to the user
  # agent" (§2) — and "Each member of the List ... MUST have a type of
  # either String or Token", carrying §2.1's parameters. The class is
  # the field type; Error, ParseError, SerializeError, the ERRORS
  # registry, Hop and Promotion nest inside it.
  #
  # parse is the recipient's view and never raises on field content,
  # with the diagnostic leniency §2.1 demands: a field whose syntax is
  # not a Structured Field Value, or whose List carries any member that
  # is not a String or Token, is the ENTIRE field ignored (RFC 9651
  # §2.2 — §2 defines no other handling for members), answering the
  # shared frozen empty value, the same answer an absent field gives;
  # while parameters NEVER fail the field — unknown parameters and
  # known parameters of a type §2.1 does not allow are preserved in the
  # Hop's data and ignored semantically (§2.1: "Unrecognised parameters
  # MUST be ignored"; §2.1.5's own quoted-string error example parses,
  # its error a String). The lenient parse is the strict walk with the
  # parameter checks not applied — never the strict walk rescued — so
  # the two policies cannot drift. A String is one field value; an
  # Array is the field's lines, combined with ", " (RFC 9651 §4.2) — a
  # List has no last-wins, the members concatenate. A wrong input type
  # is a caller bug and raises TypeError.
  #
  # parse! is strict truth: the List failure wrapped with its message
  # and byte offset, then §2's member constraint and the five §2.1
  # parameter constraints, the first offender in List order raised
  # positioned — the member's identifier offset, the parameter's VALUE
  # offset (just past the "="; the key's end for the valueless form).
  # The positioning Scan runs only on that error path. valid? answers
  # the same question with a boolean and never raises.
  #
  # The answer is a frozen value object: hops (the Hop members in wire
  # order), first/last naming §2's two ends, the typed readers on each
  # Hop (error, next_hop, next_protocol, received_status, details — nil
  # when the parameter is absent or wrong-typed) beside the raw #[]
  # and #params, the canonical to_s ("" when nothing is held), and
  # class-checked canonical equality. to_s and construction are ALWAYS
  # strict, in every family gem: a sender never puts garbage on the
  # wire — the identifier is a plain String (emits quoted) or a
  # Fast::SFV::Token (emits bare), the class the wire-type tag; the
  # five §2.1 parameters carry their sections' types.
  #
  # Two operations sit on the value: append (§2's append-yourself —
  # "intermediaries SHOULD preserve the existing members of the field"
  # — the received members in order, this intermediary's member
  # appended as the LAST, a new frozen value) and promote (§2's
  # trailer-promotion algorithm, spec-exact: the leftmost header
  # member matching each trailer member by value characters across the
  # String and Token forms, parameters ignored, replaced in its
  # entirety, the trailer removed when nothing remains — answering a
  # frozen Promotion).
  #
  # The registry is Fast::ProxyStatus::ERRORS — §2.3's 32 proxy error
  # types pinned as frozen data in document order, each with its
  # recommended HTTP status code (an Integer, or the RFC's own prose
  # for http_request_error and proxy_internal_response), its
  # response-only flag and its extra parameters, with
  # registered?/recommended_status/response_only?/extra_parameters
  # answering unknown names with nil/false. The registry NEVER gates a
  # parse or an emit: an unknown error type parses, emits and
  # round-trips untouched — future registrations never break old gem
  # versions.
  #
  # Cache-Status and Targeted Cache Control (RFC 9211/9213) are the
  # next entries of this gem's map; this class carries the hop-list
  # plumbing they will sit beside, and nothing beyond what
  # Proxy-Status itself needs.
  class ProxyStatus
  end
end
