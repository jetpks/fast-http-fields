# frozen_string_literal: true

module Fast
  module ClientCert
    # The RFC 9440 §2.1 armor lines, the text a PEM certificate block
    # is wrapped in.
    BEGIN_ARMOR = "-----BEGIN CERTIFICATE-----"
    END_ARMOR = "-----END CERTIFICATE-----"
    # The colon that delimits a Byte Sequence on both ends (§2.1:
    # "delimited with colons on either side").
    COLON = 0x3A
    private_constant :BEGIN_ARMOR, :END_ARMOR, :COLON

    # The base64 interior a ":<base64>:" value must carry: alphabet
    # characters with padding only at the end (RFC 4648 §4).
    BASE64 = %r{\A[A-Za-z0-9+/]*={0,2}\z}
    private_constant :BASE64

    # The RFC 9440 §2.1 string surgery, both directions — pure text
    # manipulation, no OpenSSL, no DER decoding: "it will be
    # sufficient to replace ---(BEGIN|END) CERTIFICATE--- with ':' and
    # remove line breaks in order to generate an appropriate item".
    # The PEM side trusts the armor and never validates the base64 (a
    # mangled payload becomes a field value that fails the Structured
    # Fields parse downstream — fail-closed like any malformed field);
    # the field-value side is strict: a sender never writes garbage.
    # Usage failures raise the base Error — neither a parse defect nor
    # a serialization defect; wrong input types raise TypeError.
    module_function

    # One RFC 7468 certificate block → the item's field value
    # ":<base64>:" — the §2.1 surgery: the BEGIN and END armor lines
    # exchanged for colons, the payload's line breaks removed, each
    # payload line stripped of the whitespace around it, generous the
    # way textual encodings need. Blank lines may lead and follow the
    # block; CRLF line endings are tolerated. Armor-shape failures
    # raise Error: no BEGIN line, the END missing, no payload (a
    # payload region of blank lines alone carries no payload), or
    # content other than blank lines after the END (a second block —
    # one PEM block at a time; pass an Array of blocks to
    # pems_to_field for a chain). TypeError for a non-String.
    def pem_to_field(pem)
      raise TypeError, "a PEM block is a String (got #{pem.class})" unless pem.is_a?(String)

      lines = pem.split("\n", -1)
      first = 0
      first += 1 while first < lines.size && lines[first] != BEGIN_ARMOR && blank?(lines[first])
      begins = first < lines.size && armor_line?(lines[first], BEGIN_ARMOR)
      raise Error, "the PEM block must begin with #{BEGIN_ARMOR}" unless begins

      last = lines.size - 1
      last -= 1 while last > first && lines[last] != END_ARMOR && blank?(lines[last])
      ends = last > first && armor_line?(lines[last], END_ARMOR)
      raise Error, "the PEM block must end with #{END_ARMOR}" unless ends
      unless first_armor_line(lines, first, last) == last
        raise Error, "one PEM block at a time — pass an Array of blocks for a chain"
      end

      base64 = lines[first + 1...last].map(&:strip).join
      raise Error, "the PEM block carries no payload" if base64.empty?

      ":#{base64}:"
    end

    # The inverse: ":<base64>:" → one RFC 7468 block — the base64
    # wrapped at 64 characters per line, every line (the END line
    # included) newline-terminated. The sender side is strict: the
    # value must carry colons on both ends and a whole, valid base64
    # interior, or Error is raised before anything is written.
    # TypeError for a non-String.
    def field_to_pem(field)
      raise TypeError, "a field value is a String (got #{field.class})" unless field.is_a?(String)

      base64 = base64_interior(field)
      block = "#{BEGIN_ARMOR}\n"
      index = 0
      size = base64.bytesize
      while index < size
        block << base64.byteslice(index, 64) << "\n"
        index += 64
      end
      block << END_ARMOR << "\n"
      block
    end

    # An Array of RFC 7468 blocks → the Client-Cert-Chain field value:
    # the per-block §2.1 surgery (each block through pem_to_field, its
    # armor-shape rules intact), the members joined with the canonical
    # ", " separator. The empty Array raises Error — nothing to
    # convert. TypeError for a non-Array.
    def pems_to_field(blocks)
      raise TypeError, "blocks are an Array of PEM Strings (got #{blocks.class})" unless blocks.is_a?(Array)
      raise Error, "nothing to convert — the blocks Array is empty" if blocks.empty?

      blocks.map { |block| pem_to_field(block) }.join(", ")
    end

    # The Client-Cert-Chain field value → the Array of RFC 7468 blocks
    # it carries, in order: the members located by the substrate's
    # region scan, whose boundaries are parameter-aware — a comma
    # inside a quoted parameter value (§4.2.5) never splits a member —
    # each member's VALUE converted exactly as field_to_pem demands
    # (the parameters are metadata the PEM conversion does not carry;
    # the value alone holds the DER bytes, and a member that is not a
    # whole :base64: item names that member's own value in its error).
    # A field value that is not a Structured Fields List raises the
    # base Error carrying the region scan's own message. The empty
    # value answers no blocks. TypeError for a non-String.
    def field_to_pems(field)
      raise TypeError, "a field value is a String (got #{field.class})" unless field.is_a?(String)
      return [].freeze if field.empty?

      regions = SFV.regions_list(field)
      regions.members.map do |member|
        value = regions.combined.byteslice(member.value_start, member.value_end - member.value_start)
        field_to_pem(value)
      end
    rescue SFV::ParseError => e
      raise Error, e.message
    end

    # A line that carries nothing but whitespace: the blank lines a
    # textual encoding may pad a block with.
    def blank?(line)
      line.empty? || line.strip.empty?
    end

    # Is the line one of the armor lines? Exact when the text is
    # clean — the allocation-free compare — with the stripped compare
    # behind it for a trailing CR (CRLF text) or padding whitespace.
    def armor_line?(line, armor)
      line == armor || line.strip == armor
    end

    # The first armor-shaped line ("-----") at or after +first+ and
    # before +last+: the END when the block is one. Anything earlier —
    # a second block's armor inside the payload region — is content
    # the one block does not carry. Base64 has no "-", so a payload
    # line never answers here.
    def first_armor_line(lines, first, last)
      index = first + 1
      index += 1 while index < last && !lines[index].start_with?("-----")
      index
    end

    # The whole base64 interior of one ":<base64>:" field value,
    # validated before anything is written: colons on both ends, a
    # non-empty interior of alphabet characters with padding only at
    # the end, and a length that is a multiple of four — the shape
    # §2.1 states ("the binary DER certificate is encoded using
    # base64 ... and delimited with colons on either side"). A value
    # that is not one raises Error.
    def base64_interior(field)
      colons = field.bytesize > 2 && field.getbyte(0) == COLON && field.getbyte(-1) == COLON
      base64 = colons ? field.byteslice(1, field.bytesize - 2) : nil
      unless base64 && !base64.empty? && BASE64.match?(base64) && (base64.bytesize % 4).zero?
        raise Error, "the value is not a :base64: item (got #{field.inspect})"
      end

      base64
    end

    private_class_method :blank?, :armor_line?, :first_armor_line, :base64_interior
  end
end
