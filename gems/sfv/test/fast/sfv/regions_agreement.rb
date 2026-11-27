# frozen_string_literal: true

require "json"
require "fast/sfv"

# The full-corpus agreement check: the region scan walks the Parser's
# own §4.2 grammar, so over every record the httpwg corpus carries —
# all 1607, not a sample — the two must agree. A record the parse
# accepts, the scan accepts, with spans that re-parse to exactly what
# the parse kept; a record the parse rejects, the scan rejects with
# its own positioned ParseError. The corpus is the same vendored
# corpus corpus.rb reads, loaded here independently so this file
# stands alone.
AGREEMENT_FILES = Dir.glob(File.expand_path("../../corpus/*.json", __dir__)).sort
AGREEMENT = AGREEMENT_FILES.to_h { |path| [File.basename(path, ".json"), JSON.parse(File.read(path))] }

# The scan and parse entry points each §4.2 shape walks.
AGREEMENT_ENTRIES = {
  "item" => [Fast::SFV.method(:regions_item), Fast::SFV.method(:parse_item)],
  "list" => [Fast::SFV.method(:regions_list), Fast::SFV.method(:parse_list)],
  "dictionary" => [Fast::SFV.method(:regions_dict), Fast::SFV.method(:parse_dict)]
}.freeze

describe "the region scan agrees with the parse over the full corpus" do
  it "loads the 20 root parse files and pins the record count at 1607" do
    expect(AGREEMENT_FILES.size).to be(:==, 20)
    expect(AGREEMENT.values.sum(&:size)).to be(:==, 1607)
  end

  # One member's agreement: the whole extent re-parses standalone to
  # exactly the member the parse kept (the canonical form is the
  # equivalence both sides answer), and the parameter group agrees —
  # the same keys in the same order, each valued parameter's slice
  # re-parsing to the value the parse kept, each valueless one's span
  # empty at its key's end. An empty value span is the valueless form
  # (§4.2.3.2 step 2.5's Boolean true): a valued Boolean true parses
  # to the same value, so the span is the discriminator.
  def expect_member_agreement(region, member, shape, combined, key)
    text = combined.byteslice(region.start, region.end - region.start)
    reparsed =
      case shape
      when "dictionary" then Fast::SFV.parse_dict(text)[key]
      when "list" then Fast::SFV.parse_list(text)[0]
      else Fast::SFV.parse_item(text)
      end
    expect(reparsed.to_s).to be(:==, member.to_s)

    scanned = {}
    region.params.each do |param|
      scanned[combined.byteslice(param.key_start, param.key_end - param.key_start)] = param
    end
    expect(scanned.keys).to be(:==, member.params.keys)
    member.params.each do |param_key, value|
      param = scanned[param_key]
      if param.value_start == param.value_end
        expect(param.value_start).to be(:==, param.key_end)
        expect(value).to be(:equal?, true)
      else
        slice = combined.byteslice(param.value_start, param.value_end - param.value_start)
        rescanned = Fast::SFV.parse_item(slice).value
        expect(rescanned.class).to be(:==, value.class)
        expect(rescanned.to_s).to be(:==, value.to_s)
      end
    end
  end

  AGREEMENT.each do |file_name, records|
    describe file_name do
      records.each do |record|
        it record["name"] do
          shape = record["header_type"]
          raw = record["raw"]
          scan_entry, parse_entry = AGREEMENT_ENTRIES.fetch(shape)
          combined = raw.join(", ")

          parsed = begin
            parse_entry.call(raw)
          rescue Fast::SFV::ParseError
            nil
          end
          if parsed.nil?
            # The parse rejected: the scan walks the same grammar and
            # rejects too — the same contract, never a foreign class.
            error = nil
            begin
              scan_entry.call(raw)
            rescue Fast::SFV::ParseError => e
              error = e
            end
            expect(error).to be(:kind_of?, Fast::SFV::ParseError)
            expect(error.offset).to be(:kind_of?, Integer)
            next
          end

          regions = scan_entry.call(raw)
          # The combined field value the spans index into.
          expect(regions.combined).to be(:==, combined)

          if shape == "dictionary"
            # Every occurrence scanned, reduced by key exactly as the
            # parse's own Hash assignment reduces: the same effective
            # members in the same order.
            scanned = {}
            regions.members.each do |region|
              key = combined.byteslice(region.key_start, region.key_end - region.key_start)
              scanned[key] = region
            end
            expect(scanned.keys).to be(:==, parsed.keys)
            scanned.each do |key, region|
              expect_member_agreement(region, parsed[key], shape, combined, key)
            end
          elsif shape == "list"
            expect(regions.members.size).to be(:==, parsed.size)
            regions.members.zip(parsed).each do |region, member|
              expect_member_agreement(region, member, shape, combined, nil)
            end
          else
            expect_member_agreement(regions.members[0], parsed, shape, combined, nil)
          end
        end
      end
    end
  end
end
