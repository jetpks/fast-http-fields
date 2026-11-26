# frozen_string_literal: true

require_relative "lib/fast/priority/version"

Gem::Specification.new do |spec|
  spec.name = "fast-priority"
  spec.version = Fast::Priority::VERSION
  spec.summary = "RFC 9218 Extensible Priorities: the Priority field and the h2/h3 PRIORITY_UPDATE frame payloads."
  spec.description = <<~DESC
    Fast::Priority implements RFC 9218 Extensible Priorities — the
    Priority HTTP header field as an RFC 9651 Dictionary consumer with
    the recipient semantics (urgency, incremental, unknown-parameter
    passthrough), plus the HTTP/2 and HTTP/3 PRIORITY_UPDATE frame
    payload codecs. Built on fast-sfv, frozen value objects, strict
    emit, one runtime dependency.
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
  # `gem build gems/priority/…gemspec` form is RubyGems-impossible for a
  # nested monorepo gemspec — build from this directory.)
  spec.files = Dir.glob(["{lib}/**/*", "*.md"], File::FNM_DOTMATCH, base: File.expand_path(__dir__))
                  .select { |f| File.file?(File.expand_path(f, __dir__)) }
  spec.require_paths = ["lib"]

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/main/gems/priority/CHANGELOG.md"
  spec.metadata["documentation_uri"] = "https://github.com/jetpks/fast-http-fields/tree/main/gems/priority/docs"
  spec.metadata["rubygems_mfa_required"] = "true"

  # Exactly one runtime dependency, unconstrained: fast-sfv is the
  # family substrate this gem parses and emits through (BRIEF §2) —
  # the protocol stacks are test-group peers, never dependencies.
  spec.add_dependency "fast-sfv"
end
