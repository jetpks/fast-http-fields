# frozen_string_literal: true

# The substrate: RFC 9530's four fields are RFC 9651 Dictionaries, so
# this gem is a fast-sfv consumer, never a parser of its own. The
# stdlib digest library is the second half of the foundation (required
# by lib/fast/digest/registry.rb).
require "fast/sfv"

require_relative "digest/version"
require_relative "digest/errors"
require_relative "digest/registry"
require_relative "digest/fields"

module Fast
  # RFC 9530 Digest Fields: the four HTTP integrity fields, the
  # hash-algorithm registry as data, and digest computing over the
  # stdlib digest library.
  #
  # The two Integrity fields are Dictionaries of algorithm key =>
  # digest Byte Sequence — ContentDigest (§2: "a hashing algorithm
  # applied to the actual message content") and ReprDigest (§3:
  # "applied to the entire selected representation data"). The two
  # preference fields are Dictionaries of algorithm key => Integer
  # 0..10 — WantContentDigest and WantReprDigest (§4: "1 is the least
  # preferred, 10 is the most preferred, and a value of 0 means 'not
  # acceptable'"). The class names carry the content-versus-
  # representation distinction the RFC 3230 history demands (§1.3,
  # Appendix E), the .of helpers name it again on the compute side, and
  # class-checked equality keeps a ContentDigest from ever equaling a
  # ReprDigest.
  #
  # parse is the recipient's view and never raises on field content: a
  # malformed field, or a field whose Dictionary carries any member
  # violating the field's constraint, is the ENTIRE field ignored (RFC
  # 9651 §2.2 — RFC 9530 defines no other handling), answering the
  # empty value object, the same answer an absent field gives. No
  # member-level filtering: a valid member beside a bad one drops with
  # the field. Unknown algorithm keys pass through as parsed, SFV
  # parameters ride along, and "" is the valid empty Dictionary. A
  # String is one field value; an Array is the field's lines, combined
  # with ", " (RFC 9651 §4.2) — the trailer-fields entry point, §2/§3's
  # "MAY be merged into the header section". A wrong input type is a
  # caller bug and raises TypeError.
  #
  # parse! is strict truth: the Dictionary failure wrapped with its
  # message and byte offset, then the member constraints — the first
  # offender raises ParseError positioned at that member's VALUE in the
  # combined field value. valid? answers the same question with a
  # boolean and never raises.
  #
  # The answer is a frozen value object: members (the Fast::SFV::Item
  # view), [] (the bare value — the digest bytes, so the day-one idiom
  # parsed["sha-256"] == Digest::SHA256.digest(body) holds bytewise),
  # the canonical to_s ("" when nothing is held), canonical-wire-form
  # equality within the class. to_s and construction are ALWAYS strict,
  # in every family gem: a sender never puts garbage on the wire —
  # byte-sequence values must be Strings tagged ASCII-8BIT, preference
  # values Integers 0..10, keys Structured Fields keys.
  #
  # The registry is Fast::Digest::ALGORITHMS — RFC 9530 §7.2 Table 2's
  # eight entries pinned as frozen data (sha-512 and sha-256 Active, the
  # other six Deprecated, the status advisory and never a gate), with
  # unknown keys passing through: future registrations never break old
  # gem versions. Fast::Digest.compute answers exactly the stdlib's
  # bytes for sha-256, sha-512, md5 and sha; the four checksum entries
  # (unixsum, unixcksum, adler, crc32c) and unknown keys raise
  # Fast::Digest::Error naming the key — their digest values pass
  # through the fields bytewise, carried on the wire, never computed or
  # verified locally.
  #
  # Inside this module a bare Digest resolves to Fast::Digest, so every
  # stdlib reference spells the leading scope operator ::Digest::SHA256
  # (lib/fast/digest/registry.rb).
  module Digest
  end
end
