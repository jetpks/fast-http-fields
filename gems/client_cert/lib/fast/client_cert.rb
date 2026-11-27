# frozen_string_literal: true

# The substrate: RFC 9440's two fields are an RFC 9651 Item and an
# RFC 9651 List, so this gem is a fast-sfv consumer, never a parser
# of its own. The DER certificate bytes are opaque throughout: no
# OpenSSL, no DER decoding — the Structured Fields grammar and the
# §2.1 string surgery carry everything.
require "fast/sfv"

require_relative "client_cert/version"
require_relative "client_cert/errors"
require_relative "client_cert/cert"
require_relative "client_cert/chain"
require_relative "client_cert/pem"

module Fast
  # RFC 9440 Client-Cert: the two request fields a TLS-terminating
  # reverse proxy sends to convey the client certificate of a mutually
  # authenticated TLS connection, and the pure-Ruby PEM surgery of
  # §2.1 in both directions.
  #
  # Fast::ClientCert::Cert is the Client-Cert field (§2.2): "This
  # field contains the end-entity certificate used by the client in
  # the TLS handshake" — one Item carrying the certificate's DER bytes
  # as a Byte Sequence (§2.1: "the binary DER certificate is encoded
  # using base64 ... and delimited with colons on either side"). A
  # recipient that cannot read the field has no certificate: parse
  # answers nil, the unauthenticated answer the §4 security story
  # demands ("Access control decisions based on the client certificate
  # (or lack thereof)" are the origin server's).
  #
  # Fast::ClientCert::Chain is the Client-Cert-Chain field (§2.3): the
  # validation chain as a List of Byte Sequences, "The order is the
  # same as the ordering in TLS" — and it "MAY have a list of values
  # or occur multiple times in a request", so an Array of field lines
  # is its native split form and Chain#split cuts a held chain back
  # into per-instance lines. A malformed field, or any member that is
  # not a Byte Sequence, is the ENTIRE field ignored: the shared
  # frozen empty value, the same answer an absent field gives.
  #
  # The four PEM helpers (pem_to_field, field_to_pem, pems_to_field,
  # field_to_pems) are the §2.1 string surgery both directions: "it
  # will be sufficient to replace ---(BEGIN|END) CERTIFICATE--- with
  # ':' and remove line breaks in order to generate an appropriate
  # item", and the inverse — the base64 wrapped at 64 characters per
  # line, every line newline-terminated (RFC 7468's form).
  #
  # parse is the recipient's view and never raises on field content;
  # parse! is strict truth with byte offsets; valid? mirrors it with a
  # boolean; to_s and construction are always strict; results are
  # frozen value objects; one runtime dependency, fast-sfv. RFC 9440
  # is Informational — the README carries the note.
  module ClientCert
    # The Byte Sequence tag: a String tagged ASCII-8BIT IS the Byte
    # Sequence on the wire (RFC 9651 §3.3.5 — the encoding is the
    # wire-type tag), so the constraint below reads the same fact a
    # serialization would, and a UTF-8 String would emit as a quoted
    # sf-string, not ":base64:".
    BINARY = Encoding::ASCII_8BIT
    private_constant :BINARY

    # The one constraint §2.1 and §2.3 state — "The headers in this
    # document encode certificates as Byte Sequences" — read by both
    # fields' strict parses AND both constructions, so the four
    # boundaries cannot drift. A Token is a String whose class is the
    # token's wire-type tag, so it is refused by class: a
    # binary-tagged Token would slip through the encoding check alone
    # and emit as a token, not a Byte Sequence.
    module Checks
      module_function

      # Is +value+ the Byte Sequence shape §2.1/§2.3 demand? A
      # DER-encoded X.509 certificate is never zero bytes (§2.1: "the
      # binary data is a DER-encoded X.509 certificate"), so the empty
      # byte sequence "::" is refused here — the one seam every
      # boundary reads: both strict parses, both constructions, and
      # both fail-closed falls.
      def byte_sequence?(value)
        value.is_a?(String) && !value.is_a?(SFV::Token) && value.encoding == BINARY && !value.empty?
      end

      # What a constraint error shows of the offender: the value's
      # inspect when it is String-shaped, its class otherwise — an
      # Item unwrapped first (an inner list shows its own class,
      # Fast::SFV::InnerList).
      def shown(shape)
        value = shape.is_a?(SFV::Item) ? shape.value : shape
        value.is_a?(String) ? value.inspect : value.class
      end
    end
    private_constant :Checks
  end
end
