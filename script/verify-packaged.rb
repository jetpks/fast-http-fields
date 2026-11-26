#!/usr/bin/env ruby
# frozen_string_literal: true

require "tmpdir"

# Per-gem packaged-gem verify (the release workflow's pre-publish proof),
# generalized for the five-gem monorepo.
#
#   ruby script/verify-packaged.rb <gem_name> [expected_version]
#   ruby script/verify-packaged.rb              # every pkg/*.gem present
#
# The five-gem map (gem name => [require path, VERSION constant]). The
# constant is explicit, never camelized: camelize("sfv") is "Sfv", but the
# module is Fast::SFV — this map is the single place the
# require-path/constant pairs live for the whole repo. All five entries
# exist from day one (the generalization); the no-argument loop verifies
# every gem that has been built into pkg/.
#
# With an expected version (the tag's, its "<gem>-v" prefix stripped), the
# built package's OWN version is asserted before any install: a mismatch
# aborts naming both versions and the package file — a tag cut on a commit
# that diverged from the gemspec never publishes. The assertion needs no
# network: it reads the .gem's own spec and nothing else.
#
# Contract per gem: install pkg/<gem_name>-*.gem into an ISOLATED GEM_HOME
# ($RUNNER_TEMP/gemhome-<gem_name>, per-gem suffixed so a loop run never
# collides; runtime dependencies resolve from rubygems — fast-sfv's
# dependents resolve the published gem), then require the require path
# from OUTSIDE the checkout (cwd moves to the isolated GEM_HOME — the
# checkout's lib/ is never on the load path) and print the gem's VERSION
# constant. The probe runs in a CHILD ruby process with GEM_HOME already
# in its environment: rubygems resolves its gem paths at interpreter
# boot, so an in-process ENV["GEM_HOME"] switch would be too late. This
# is where a file missing from spec.files or a require-path mistake dies
# — before publishing, not after. Any failure exits 1, loud.

GEMS = {
  "fast-sfv" => ["fast/sfv", "Fast::SFV"],
  "fast-priority" => ["fast/priority", "Fast::Priority"],
  "fast-digest" => ["fast/digest", "Fast::Digest"],
  "fast-proxy-status" => ["fast/proxy_status", "Fast::ProxyStatus"],
  "fast-client-cert" => ["fast/client_cert", "Fast::ClientCert"]
}.freeze

# The checkout the pkg/ globs resolve from, captured before anything
# chdirs: verify's probe step moves the process into the isolated
# GEM_HOME, so a later loop iteration's relative "pkg/..." glob would
# resolve against that GEM_HOME and find nothing — the no-argument loop
# would die after the first gem. Every pkg/ glob is rooted here instead.
CHECKOUT = Dir.pwd

# One named gem and its optional expected version (the name must be in
# the map); with no arguments, every gem that has been built into pkg/.
# More than two arguments is a usage error: the multi-name form is
# retired — a version argument does not compose with a name list.
def target_gems(argv)
  abort "usage: ruby script/verify-packaged.rb <gem_name> [expected_version]" if argv.size > 2

  names = argv.first(1)
  names.each do |name|
    abort "verify-packaged: #{name} is not in the five-gem map (#{GEMS.keys.join(', ')})" unless GEMS.key?(name)
  end
  return names if names.any?

  built = GEMS.keys.select { |name| Dir.glob(File.join(CHECKOUT, "pkg/#{name}-*.gem")).any? }
  abort "verify-packaged: no pkg/*.gem found — build the gem(s) first" if built.empty?
  built
end

# The tag-version assertion (the release workflow's first act, run
# before any install): the built package's own version, read straight
# off the .gem. A mismatch is a tag cut on a diverged commit — loud,
# both versions and the package file named.
def assert_tag_version(gem_name, package, expected)
  return if expected.nil?

  require "rubygems/package"
  packaged = Gem::Package.new(package).spec.version.to_s
  return if packaged == expected

  abort "verify-packaged: the tag says version #{expected} but the packaged #{gem_name} is " \
        "version #{packaged} (#{File.basename(package)}) — a tag cut on a diverged commit; refusing to publish"
end

def verify(gem_name, expected)
  require_path, constant = GEMS.fetch(gem_name)

  package = Dir.glob(File.join(CHECKOUT, "pkg/#{gem_name}-*.gem")).first
  abort "verify-packaged: no pkg/#{gem_name}-*.gem found — build the gem first" unless package

  assert_tag_version(gem_name, package, expected)

  gem_home = File.join(ENV["RUNNER_TEMP"] || Dir.tmpdir, "gemhome-#{gem_name}")
  isolated = { "GEM_HOME" => gem_home, "GEM_PATH" => gem_home }

  install = system(isolated, "gem", "install", "--no-document", package)
  abort "verify-packaged: gem install failed for #{package}" unless install

  probe = <<~RUBY
    require ARGV[0]
    puts Object.const_get(ARGV[1]).const_get(:VERSION)
  RUBY

  Dir.chdir(gem_home) # outside the checkout: the checkout's lib/ is never on the load path
  probed = system(isolated, RbConfig.ruby, "-e", probe, require_path, constant)
  abort "verify-packaged: the packaged #{gem_name} failed its require/VERSION probe" unless probed

  puts "VERIFY_PACKAGED_OK #{gem_name} #{require_path} #{constant}"
end

expected_version = ARGV[1]
target_gems(ARGV).each { |gem_name| verify(gem_name, expected_version) }
