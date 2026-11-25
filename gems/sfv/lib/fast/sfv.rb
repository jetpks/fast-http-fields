# frozen_string_literal: true

require_relative "sfv/version"
require_relative "sfv/errors"
require_relative "sfv/types"
require_relative "sfv/parser"

module Fast
  # RFC 9651 Structured Field Values — the syntax substrate of the
  # fast-http-fields family: every other field gem parses and emits
  # through SFV.
  #
  # The parse side is this iteration's surface. The three typed entry
  # points — parse_item, parse_list, parse_dict — are strict (RFC 9651
  # §1.1 forbids tolerance): field content that is not a Structured Field
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
  module SFV
  end
end
