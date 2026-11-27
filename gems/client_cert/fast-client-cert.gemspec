# frozen_string_literal: true

require_relative "lib/fast/client_cert/version"

Gem::Specification.new do |spec|
  spec.name = "fast-client-cert"
  spec.version = Fast::ClientCert::VERSION
  spec.summary = "RFC 9440 request fields: Client-Cert and Client-Cert-Chain."
  spec.description = <<~DESC
    Fast::ClientCert implements RFC 9440 — the two request fields a
    TLS-terminating reverse proxy sends to convey the client
    certificate of a mutually authenticated TLS connection, as frozen
    value objects over fast-sfv: Cert (the Client-Cert field, a
    singleton Byte Sequence Item carrying the end-entity certificate
    with fail-closed recipient semantics — a malformed field answers
    nil, the unauthenticated connection) and Chain (the
    Client-Cert-Chain field, a List of Byte Sequences in TLS order
    that MAY split across field instances), plus the four pure-Ruby
    PEM conversion helpers — the RFC 9440 2.1 string surgery in both
    directions, no OpenSSL, DER bytes opaque. One runtime dependency,
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
  # `gem build gems/client_cert/…gemspec` form is RubyGems-impossible for a
  # nested monorepo gemspec — build from this directory.)
  spec.files = Dir.glob(["{lib}/**/*", "*.md", "LICENSE"], File::FNM_DOTMATCH, base: File.expand_path(__dir__))
                  .select { |f| File.file?(File.expand_path(f, __dir__)) }
  spec.require_paths = ["lib"]

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/main/gems/client_cert/CHANGELOG.md"
  # The diátaxis documentation tree this gem ships under docs/.
  spec.metadata["documentation_uri"] = "https://github.com/jetpks/fast-http-fields/tree/main/gems/client_cert/docs"
  spec.metadata["rubygems_mfa_required"] = "true"

  # Exactly one runtime dependency: fast-sfv, 0.2 or later within the
  # 0.x series — the Structured Field Values substrate this gem parses
  # and emits through; the string surgery needs nothing else, being
  # pure Ruby.
  spec.add_dependency "fast-sfv", "~> 0.2"
end
