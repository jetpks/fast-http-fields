# frozen_string_literal: true

require "fast/digest"

# The construction boundary's error contract: a caller-supplied value
# that is classless (a BasicObject descendant) is refused with
# SerializeError — the class the whole emit path documents — never a
# raw NoMethodError out of a guard that called a method on the value it
# was rejecting. The fuzz harness's emit campaign is the exhaustive
# check over its hostile-value pool.
describe "the construction boundary" do
  it "refuses classless members with SerializeError" do
    [Fast::Digest::ContentDigest, Fast::Digest::ReprDigest,
     Fast::Digest::WantContentDigest, Fast::Digest::WantReprDigest].each do |klass|
      expect { klass.new(BasicObject.new) }.to raise_exception(Fast::Digest::SerializeError)
    end
  end

  it "refuses a classless member value with SerializeError" do
    [Fast::Digest::ContentDigest, Fast::Digest::ReprDigest,
     Fast::Digest::WantContentDigest, Fast::Digest::WantReprDigest].each do |klass|
      expect { klass.new({ "sha-256" => BasicObject.new }) }.to raise_exception(Fast::Digest::SerializeError)
    end
  end
end
