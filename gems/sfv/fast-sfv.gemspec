# frozen_string_literal: true

require_relative "lib/fast/sfv/version"

Gem::Specification.new do |spec|
  spec.name = "fast-sfv"
  spec.version = Fast::SFV::VERSION
  spec.summary = "RFC 9651 Structured Field Values for Ruby: strict parse, canonical emit."
  spec.description = <<~DESC
    Fast::SFV implements RFC 9651 Structured Field Values — Items, Lists,
    and Dictionaries with parameters — the syntax layer every other
    fast-http-fields gem builds on. Strict parse, canonical emit, frozen
    value objects, byte-index scanning, zero runtime dependencies.
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
  # packaging a .gem with no lib/. (I51 judge ruling: the repo-root
  # `gem build gems/sfv/…gemspec` form is RubyGems-impossible for a nested
  # monorepo gemspec — build from this directory.)
  spec.files = Dir.glob(["{lib}/**/*", "*.md"], File::FNM_DOTMATCH, base: File.expand_path(__dir__))
                  .select { |f| File.file?(File.expand_path(f, __dir__)) }
  spec.require_paths = ["lib"]

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/main/gems/sfv/CHANGELOG.md"
  spec.metadata["rubygems_mfa_required"] = "true"

  # NO runtime dependencies: fast-sfv is the family substrate (BRIEF §2) —
  # it depends on nothing; the four dependents will declare exactly
  # fast-sfv as their only runtime dependency.
end
