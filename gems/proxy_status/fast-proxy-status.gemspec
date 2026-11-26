# frozen_string_literal: true

require_relative "lib/fast/proxy_status/version"

Gem::Specification.new do |spec|
  spec.name = "fast-proxy-status"
  spec.version = Fast::ProxyStatus::VERSION
  spec.summary = "RFC 9209 Proxy-Status: the HTTP response field that conveys how intermediaries handled a response."
  spec.description = <<~DESC
    Fast::ProxyStatus implements RFC 9209 Proxy-Status — the HTTP
    response field as a frozen value object over fast-sfv: a List of
    parameterized members, one per intermediary that handled the
    response, the first closest to the origin server. The five
    section 2.1 parameters with typed readers on the member value
    object, the diagnostic leniency of RFC 9651 2.2 (a malformed field
    is treated as absent; unknown and wrong-typed parameters are
    preserved in the data and ignored semantically), the
    append-yourself operation, the section 2 trailer-promotion
    algorithm, and the 32-entry section 2.3 proxy error type registry
    as frozen data with unknown passthrough. One runtime dependency,
    fast-sfv.
  DESC

  spec.authors = ["Eric Jacobs"]
  spec.license = "MIT"
  spec.homepage = "https://github.com/jetpks/fast-http-fields"

  spec.required_ruby_version = ">= 3.4"
  spec.required_rubygems_version = ">= 3.5.3"

  # RubyGems loads gemspecs via eval: __dir__ is the dirname of the path AS
  # PASSED (relative when invoked relatively), Dir.glob(base:) returns
  # BASE-RELATIVE names, and `gem build` validates/packages spec.files
  # against the INVOCATION cwd. Keep the names gemspec-dir-relative (the
  # form that packages correctly from this directory) but resolve the
  # filter against the gemspec dir so foreign-cwd loads see the true file
  # list — and a foreign-cwd `gem build` fails LOUDLY instead of silently
  # packaging a .gem with no lib/. (The repo-root
  # `gem build gems/proxy_status/…gemspec` form is RubyGems-impossible for a
  # nested monorepo gemspec — build from this directory.)
  spec.files = Dir.glob(["{lib}/**/*", "*.md"], File::FNM_DOTMATCH, base: File.expand_path(__dir__))
                  .select { |f| File.file?(File.expand_path(f, __dir__)) }
  spec.require_paths = ["lib"]

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/main/gems/proxy_status/CHANGELOG.md"
  spec.metadata["documentation_uri"] = "https://github.com/jetpks/fast-http-fields/tree/main/gems/proxy_status/docs"
  spec.metadata["rubygems_mfa_required"] = "true"

  # Exactly one runtime dependency, unconstrained: fast-sfv is the
  # family substrate this gem parses and emits through — Proxy-Status
  # is a Structured Field Values List, so there is nothing to compute
  # and no stdlib to add.
  spec.add_dependency "fast-sfv"
end
