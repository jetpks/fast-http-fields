# frozen_string_literal: true

require "fast/proxy_status"

# The construction and promotion boundaries' error contract: a
# caller-supplied value that is classless (a BasicObject descendant) is
# refused with the documented class — SerializeError for field content
# at a construction boundary, TypeError for a wrong input type at a
# field argument — never a raw NoMethodError out of a guard that called
# a method on the value it was rejecting. The fuzz harness's emit
# campaign is the exhaustive check over its hostile-value pool.
describe "the construction boundary" do
  it "refuses classless field members with SerializeError" do
    expect { Fast::ProxyStatus.new(BasicObject.new) }.to raise_exception(Fast::ProxyStatus::SerializeError)
    expect { Fast::CacheStatus.new(BasicObject.new) }.to raise_exception(Fast::CacheStatus::SerializeError)
  end

  it "refuses a classless member and parameter with SerializeError" do
    expect { Fast::ProxyStatus::Hop.new(BasicObject.new) }.to raise_exception(Fast::ProxyStatus::SerializeError)
    expect { Fast::ProxyStatus::Hop.new("h", { "k" => BasicObject.new }) }
      .to raise_exception(Fast::ProxyStatus::SerializeError)
    expect { Fast::ProxyStatus::Hop.new("h", { "error" => BasicObject.new }) }
      .to raise_exception(Fast::ProxyStatus::SerializeError)
  end

  it "refuses a classless append member and parameter with SerializeError" do
    expect { Fast::ProxyStatus.append(nil, BasicObject.new) }
      .to raise_exception(Fast::ProxyStatus::SerializeError)
    expect { Fast::CacheStatus.append(nil, BasicObject.new) }
      .to raise_exception(Fast::CacheStatus::SerializeError)
    expect { Fast::CacheStatus.append(nil, "c", { "fwd" => BasicObject.new }) }
      .to raise_exception(Fast::CacheStatus::SerializeError)
  end

  it "answers TypeError for a classless field argument, never NoMethodError" do
    expect { Fast::ProxyStatus.append(BasicObject.new, "h") }.to raise_exception(TypeError)
    expect { Fast::CacheStatus.append(BasicObject.new, "c") }.to raise_exception(TypeError)
    expect { Fast::ProxyStatus.promote(BasicObject.new, nil) }.to raise_exception(TypeError)
    expect { Fast::ProxyStatus.promote("h", BasicObject.new) }.to raise_exception(TypeError)
  end

  it "refuses classless TargetedCacheControl members and values with SerializeError" do
    expect { Fast::TargetedCacheControl.new(BasicObject.new) }
      .to raise_exception(Fast::TargetedCacheControl::SerializeError)
    expect { Fast::TargetedCacheControl.new({ "max-age" => BasicObject.new }) }
      .to raise_exception(Fast::TargetedCacheControl::SerializeError)
    expect { Fast::TargetedCacheControl.new({ "no-store" => BasicObject.new }) }
      .to raise_exception(Fast::TargetedCacheControl::SerializeError)
  end
end
