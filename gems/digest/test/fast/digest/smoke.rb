# frozen_string_literal: true

# The harness proof: this file only runs if config/sus.rb routed
# gems/digest/lib onto the load path (the require below resolves) and
# gems/digest/test into the run (this file was discovered).
require "fast/digest"

describe Fast::Digest do
  it "loads the scaffold and carries its version" do
    expect(Fast::Digest).to be(:kind_of?, Module)
    expect(Fast::Digest::VERSION).to be(:==, "0.1.2")
  end
end
