# frozen_string_literal: true

# The harness proof: this file only runs if config/sus.rb routed
# gems/proxy_status/lib onto the load path (the require below resolves)
# and gems/proxy_status/test into the run (this file was discovered).
require "fast/proxy_status"

describe Fast::ProxyStatus do
  it "loads the scaffold and carries its version" do
    expect(Fast::ProxyStatus).to be(:kind_of?, Class)
    expect(Fast::ProxyStatus::VERSION).to be(:==, "0.1.1")
  end
end
