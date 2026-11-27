# frozen_string_literal: true

require "fast/sfv"

# The emit boundary's error contract: a caller-supplied value that is
# classless (a BasicObject descendant) is refused with SerializeError —
# the class the whole emit path documents — never a raw NoMethodError
# out of a guard that called a method on the value it was rejecting.
# These pin the contract per entry point; the fuzz harness's emit
# campaign is the exhaustive check over its hostile-value pool.
describe "the emit boundary" do
  it "refuses a classless item, list and dictionary with SerializeError" do
    expect { Fast::SFV.serialize_item(BasicObject.new) }.to raise_exception(Fast::SFV::SerializeError)
    expect { Fast::SFV.serialize_list(BasicObject.new) }.to raise_exception(Fast::SFV::SerializeError)
    expect { Fast::SFV.serialize_dict(BasicObject.new) }.to raise_exception(Fast::SFV::SerializeError)
  end

  it "refuses a classless bare item with SerializeError" do
    expect { Fast::SFV::Item.new(BasicObject.new, {}).to_s }.to raise_exception(Fast::SFV::SerializeError)
  end

  it "refuses classless inner-list items and parameters with SerializeError" do
    expect { Fast::SFV::InnerList.new(BasicObject.new, {}).to_s }.to raise_exception(Fast::SFV::SerializeError)
    expect { Fast::SFV::InnerList.new([], BasicObject.new).to_s }.to raise_exception(Fast::SFV::SerializeError)
  end

  it "refuses a classless date value and display-string value with SerializeError" do
    expect { Fast::SFV::Date.new(BasicObject.new).to_s }.to raise_exception(Fast::SFV::SerializeError)
    expect { Fast::SFV::DisplayString.new(BasicObject.new).to_s }.to raise_exception(Fast::SFV::SerializeError)
  end

  it "names the classless shape in the message, never the value" do
    error = nil
    begin
      Fast::SFV.serialize_item(BasicObject.new)
    rescue Fast::SFV::SerializeError => e
      error = e
    end
    expect(error.message).to be(:==, "an Item is required (got a classless object)")
    expect(error.offset).to be(:==, 0)
  end
end
