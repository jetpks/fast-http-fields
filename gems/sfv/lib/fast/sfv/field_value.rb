# frozen_string_literal: true

module Fast
  module SFV
    # RFC 9651 §4.2's input contract and combining — the one
    # implementation every entry point reads, the parse walks and the
    # region scan alike. A String is one field value; an Array is the
    # field's lines, combined with ", " (a Rack join conforms);
    # anything else is a caller bug, TypeError. Each Array line is
    # checked before the join.
    module FieldValue
      module_function

      # The field value to walk: a String as given, or the lines
      # joined with ", " (each line a String, a subclass included).
      def of(input)
        case input
        when String
          input
        when Array
          input.each do |line|
            next if line.is_a?(String)

            got = defined?(line.class) ? line.class : "a classless object"
            raise TypeError, "an Array of String field lines is required (got #{got})"
          end
          combine_lines(input)
        else
          got = defined?(input.class) ? input.class : "a classless object"
          raise TypeError, "a String or an Array of String field lines is required (got #{got})"
        end
      end

      # §4.2 step 2, the combining of the field's lines. A line whose
      # encoding is not ASCII-compatible cannot join with anything —
      # the combine would raise Encoding::CompatibilityError
      # mid-join, a class no parse contract admits — so it is
      # rejected here, positioned at the line's start in the combined
      # value, never transcoded. A line that is ASCII-compatible but
      # carries a byte above 0x7F joins as raw bytes: the byte view
      # cannot raise mid-join (whatever the other lines' encodings),
      # and the line fails the ASCII check at its exact byte either
      # way. Lines that are all-ASCII — every valid input — take the
      # plain join: no copies, no new allocations.
      def combine_lines(lines)
        offset = 0
        high_bytes = false
        lines.each do |line|
          encoding = line.encoding
          unless encoding.ascii_compatible?
            reason = "a field line must be an ASCII-compatible encoding (got #{encoding.name})"
            raise ParseError.new("#{reason} at offset #{offset}", offset)
          end

          high_bytes = true unless line.ascii_only?
          offset += line.bytesize + 2
        end
        return lines.join(", ") unless high_bytes

        lines.map { |line| line.ascii_only? ? line : line.b }.join(", ")
      end
    end

    private_constant :FieldValue
  end
end
