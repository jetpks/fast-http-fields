# frozen_string_literal: true

require_relative "sfv/version"
require_relative "sfv/errors"
require_relative "sfv/types"
require_relative "sfv/parser"
require_relative "sfv/serializer"

module Fast
  # RFC 9651 Structured Field Values — the syntax substrate of the
  # fast-http-fields family: every other field gem parses and emits
  # through SFV.
  #
  # The parse side landed first. The three typed entry points —
  # parse_item, parse_list, parse_dict — are strict (RFC 9651 §1.1
  # forbids tolerance): field content that is not a Structured Field
  # Value of the asked shape raises Fast::SFV::ParseError, carrying the
  # byte offset where the parse stopped; an input that is neither a
  # String nor an Array of field lines raises TypeError instead, because
  # a wrong type is a caller bug, not field content. The valid_item?,
  # valid_list? and valid_dict? mirrors answer the same question with a
  # boolean and never raise.
  #
  # A String input is one field value; an Array input is the field's
  # lines, combined with ", " (§4.2's combining rule). Results are
  # deep-frozen: the Items and InnerLists, the list Array, the ordered
  # dictionary and parameter Hashes with their String keys, and every
  # String the parse produced. Tokens arrive as Symbols, byte sequences
  # as frozen ASCII-8BIT Strings, dates and display strings wrapped in
  # Fast::SFV::Date and Fast::SFV::DisplayString.
  #
  # The emit side takes those shapes back to the wire:
  # serialize_item, serialize_list and serialize_dict produce the
  # canonical §4.1 form as a fresh US-ASCII String the caller owns, or
  # nil for an empty List or Dictionary (§4.1 step 1: omit the field
  # entirely). The Ruby type of a value is its wire-type tag — an
  # Integer is an integer, a Float a decimal, a Symbol a token, a String
  # an sf-string unless it is tagged ASCII-8BIT and so a byte sequence;
  # the content never decides. Strict: any non-serializable input raises
  # Fast::SFV::SerializeError with the byte offset into the output built
  # so far — there is no coercion, so TypeError never appears on the
  # emit path. Item#to_s, InnerList#to_s, Date#to_s and
  # DisplayString#to_s are the same emit, and serialize_item answers
  # exactly item.to_s.
  module SFV
  end
end
