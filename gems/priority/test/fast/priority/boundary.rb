# frozen_string_literal: true

require "fast/priority"

# The construction and frame-emit boundaries' error contract: a
# caller-supplied value that is classless (a BasicObject descendant) is
# refused with SerializeError — the documented class of the whole emit
# path — never a raw NoMethodError out of a guard that called a method
# on the value it was rejecting. The fuzz harness's emit campaign is
# the exhaustive check over its hostile-value pool.
describe "the construction boundary" do
  it "refuses a classless urgency, incremental and unknown members with SerializeError" do
    expect { Fast::Priority::Parameters.new(urgency: BasicObject.new) }
      .to raise_exception(Fast::Priority::SerializeError)
    expect { Fast::Priority::Parameters.new(incremental: BasicObject.new) }
      .to raise_exception(Fast::Priority::SerializeError)
    expect { Fast::Priority::Parameters.new(unknown: BasicObject.new) }
      .to raise_exception(Fast::Priority::SerializeError)
    expect { Fast::Priority::Parameters.new(unknown: { "k" => BasicObject.new }) }
      .to raise_exception(Fast::Priority::SerializeError)
  end

  it "refuses a classless frame payload argument with SerializeError" do
    signal = Fast::Priority::Parameters.new
    expect { Fast::Priority::H2.encode_payload(1, BasicObject.new) }
      .to raise_exception(Fast::Priority::SerializeError)
    expect { Fast::Priority::H2.encode_payload(BasicObject.new, signal) }
      .to raise_exception(Fast::Priority::SerializeError)
    expect { Fast::Priority::H3.encode_payload(1, BasicObject.new) }
      .to raise_exception(Fast::Priority::SerializeError)
    expect { Fast::Priority::H3.encode_payload(BasicObject.new, signal) }
      .to raise_exception(Fast::Priority::SerializeError)
  end
end
