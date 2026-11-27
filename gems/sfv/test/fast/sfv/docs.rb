# frozen_string_literal: true

require "fast/sfv"

# The docs examples this spec executes as printed — the README's
# malformed-content example (its offset pin is the substrate's one
# exact offset pin, lost with the docs regeneration that re-authored
# the tree and never noted the loss) and the how-to guide's
# field-line reject-policy example.
describe "the documented examples" do
  it "raises the README's malformed-content example at offset 4" do
    error = nil
    begin
      Fast::SFV.parse_item("foo bar")
    rescue Fast::SFV::ParseError => e
      error = e
    end
    expect(error).to be(:kind_of?, Fast::SFV::ParseError)
    expect(error.offset).to be(:==, 4)
    expect(error.message).to be(:==, "unexpected content after the value at offset 4")
  end

  it "rejects the how-to guide's unjoinable field line at offset 5" do
    error = nil
    begin
      Fast::SFV.parse_list(["a=1", "b=2".encode("UTF-16LE")])
    rescue Fast::SFV::ParseError => e
      error = e
    end
    expect(error).to be(:kind_of?, Fast::SFV::ParseError)
    expect(error.offset).to be(:==, 5)
    expect(error.message).to be(:==, "a field line must be an ASCII-compatible encoding (got UTF-16LE) at offset 5")
  end
end
