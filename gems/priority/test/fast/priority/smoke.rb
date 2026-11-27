# frozen_string_literal: true

# The harness proof: this file only runs if config/sus.rb routed
# gems/priority/lib onto the load path (the require below resolves) and
# gems/priority/test into the run (this file was discovered).
require "fast/priority"

describe Fast::Priority do
  it "loads the scaffold and carries its version" do
    expect(Fast::Priority).to be(:kind_of?, Module)
    expect(Fast::Priority::VERSION).to be(:==, "0.1.1")
  end
end
