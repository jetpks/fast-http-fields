# frozen_string_literal: true

# The harness proof: this file only runs if config/sus.rb routed
# gems/sfv/lib onto the load path (the require below resolves) and
# gems/sfv/test into the run (this file was discovered).
require "fast/sfv"

describe Fast::SFV do
  it "loads the scaffold and carries its version" do
    expect(Fast::SFV).to be(:kind_of?, Module)
    expect(Fast::SFV::VERSION).to be(:==, "0.2.1")
  end
end
