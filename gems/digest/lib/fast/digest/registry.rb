# frozen_string_literal: true

# The stdlib digest library: the second oracle of this gem, beside RFC
# 9530. Required here, at the top, because the module below is named
# Fast::Digest — inside it a bare Digest resolves to Fast::Digest, so
# every stdlib reference in this file spells the leading scope operator
# ::Digest::SHA256.
require "digest"

module Fast
  module Digest
    # RFC 9530 §7.2 Table 2 — the initial "Hash Algorithms for HTTP
    # Digest Fields" registry, pinned as data: a gem that pins its RFC's
    # registry at publication passes unknown values through, so a future
    # registration never breaks an old gem version. Each value is a
    # frozen {"status" => ..., "description" => ...}; the descriptions
    # are Table 2's own text, its bracket citation keys pointing into
    # RFC 9530 §8's reference list. §5: the status "is intended to
    # provide an aid to implementation selection" — Active for sha-512
    # and sha-256, Deprecated for the other six ("MAY be used to
    # preserve integrity against corruption, but MUST NOT be used in a
    # potentially adversarial setting") — and it never gates a parse, an
    # emit or a computation here.
    ALGORITHMS = {
      "sha-512" => { "status" => "Active", "description" => "The SHA-512 algorithm." }.freeze,
      "sha-256" => { "status" => "Active", "description" => "The SHA-256 algorithm." }.freeze,
      "md5" => {
        "status" => "Deprecated",
        "description" => "The MD5 algorithm. It is vulnerable to collision attacks; see [NO-MD5] and [CMU-836068]"
      }.freeze,
      "sha" => {
        "status" => "Deprecated",
        "description" => "The SHA-1 algorithm. It is vulnerable to collision attacks; see [NO-SHA] and [IACR-2020-014]"
      }.freeze,
      "unixsum" => {
        "status" => "Deprecated", "description" => 'The algorithm used by the UNIX "sum" command.'
      }.freeze,
      "unixcksum" => {
        "status" => "Deprecated",
        "description" => 'The algorithm used by the UNIX "cksum" command.'
      }.freeze,
      "adler" => { "status" => "Deprecated", "description" => "The ADLER32 algorithm." }.freeze,
      "crc32c" => { "status" => "Deprecated", "description" => "The CRC32c algorithm." }.freeze
    }.freeze

    # The keys Fast::Digest.compute answers: the four algorithms the
    # stdlib digest library computes. Table 2's four checksum entries
    # (unixsum, unixcksum, adler, crc32c) are registered but carry no
    # local implementation, so their field values pass through bytewise
    # while compute refuses them, naming the key: the RFC 9530 registry
    # is the only source of their digest values.
    COMPUTABLE = %w[sha-256 sha-512 md5 sha].freeze
    private_constant :COMPUTABLE

    module_function

    # Is +key+ one of Table 2's eight Algorithm Keys? An unknown key
    # answers false, and passes through the fields untouched either way.
    def registered?(key)
      ALGORITHMS.key?(key)
    end

    # Table 2's Status for +key+ — "Active" or "Deprecated" — or nil for
    # a key the registry does not carry.
    def status(key)
      entry = ALGORITHMS[key]
      entry && entry["status"]
    end

    # §5: "Algorithms with a status value of 'Active' are suitable for
    # many purposes and it is RECOMMENDED that applications use these
    # algorithms." False for unknown keys.
    def active?(key)
      status(key) == "Active"
    end

    # §5: a Deprecated algorithm "MAY be used to preserve integrity
    # against corruption, but MUST NOT be used in a potentially
    # adversarial setting." False for unknown keys.
    def deprecated?(key)
      status(key) == "Deprecated"
    end

    # Can Fast::Digest.compute answer +key+? True for the four stdlib
    # algorithms, false for the four checksum entries and for unknown
    # keys.
    def computable?(key)
      COMPUTABLE.include?(key)
    end

    # The digest of +input+ under +key+ — exactly the stdlib's bytes,
    # as a frozen ASCII-8BIT String (the Byte Sequence tag: the day-one
    # comparison parsed["sha-256"] == Digest::SHA256.digest(body) holds
    # bytewise). The input is hashed bytewise whatever its encoding; a
    # non-String input is a caller bug and raises TypeError. A
    # registered checksum entry (unixsum, unixcksum, adler, crc32c) or
    # an unregistered key raises Fast::Digest::Error naming the key and
    # the reason: a usage failure, neither a parse nor a serialization
    # defect.
    def compute(key, input)
      raise TypeError, "a String is required to digest (got #{input.class})" unless input.is_a?(String)

      case key
      when "sha-256" then ::Digest::SHA256.digest(input).freeze
      when "sha-512" then ::Digest::SHA512.digest(input).freeze
      when "md5" then ::Digest::MD5.digest(input).freeze
      when "sha" then ::Digest::SHA1.digest(input).freeze
      else raise Error, uncomputable_reason(key)
      end
    end

    # Why compute cannot answer +key+: a Table 2 checksum entry this gem
    # deliberately does not compute locally, or a key RFC 9530's
    # registry does not carry.
    def uncomputable_reason(key)
      return "#{key} is not in the RFC 9530 hash algorithm registry" unless ALGORITHMS.key?(key)

      "#{key} is registered but not computable here: construct the field with its explicit digest value"
    end

    private_class_method :uncomputable_reason
  end
end
