# frozen_string_literal: true

require_relative "lib/fast/digest/version"

Gem::Specification.new do |spec|
  spec.name = "fast-digest"
  spec.version = Fast::Digest::VERSION
  spec.summary = "RFC 9530 Digest Fields: Content-Digest, Repr-Digest, Want-Content-Digest and Want-Repr-Digest."
  spec.description = <<~DESC
    Fast::Digest implements RFC 9530 Digest Fields — the four integrity
    fields as frozen value objects over fast-sfv: ContentDigest and
    ReprDigest (algorithm key => digest Byte Sequence) with the
    fail-closed recipient semantics of RFC 9651 2.2, and
    WantContentDigest and WantReprDigest (algorithm key => Integer
    0..10 preference). The hash-algorithm registry of RFC 9530 7.2
    Table 2 as frozen data with unknown-key passthrough, and digest
    computing over the stdlib digest library for sha-256, sha-512, md5
    and sha. One runtime dependency, fast-sfv.
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
  # `gem build gems/digest/…gemspec` form is RubyGems-impossible for a
  # nested monorepo gemspec — build from this directory.)
  spec.files = Dir.glob(["{lib}/**/*", "*.md"], File::FNM_DOTMATCH, base: File.expand_path(__dir__))
                  .select { |f| File.file?(File.expand_path(f, __dir__)) }
  spec.require_paths = ["lib"]

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/main/gems/digest/CHANGELOG.md"
  spec.metadata["rubygems_mfa_required"] = "true"

  # Exactly one runtime dependency, unconstrained: fast-sfv is the
  # family substrate this gem parses and emits through — the stdlib
  # digest library needs no dependency line, being a default gem.
  spec.add_dependency "fast-sfv"
end
