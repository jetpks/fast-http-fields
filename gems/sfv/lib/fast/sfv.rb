# frozen_string_literal: true

require_relative "sfv/version"

module Fast
  # RFC 9651 Structured Field Values — the syntax substrate of the
  # fast-http-fields family: every other field gem parses and emits
  # through SFV. This scaffold carries the module and its version; the
  # grammar (strict parse, then canonical serialization) lands under
  # lib/fast/sfv/ with the next iterations.
  module SFV
  end
end
