# frozen_string_literal: true

require "covered/sus"
include Covered::Sus

# Monorepo harness (fast-llm's .rspec pattern, translated to sus): every
# gems/<name>/lib onto the load path, every gems/<name>/test into the run.
# Glob-driven — a new gem directory needs no harness edit.
def add_default_load_paths
  super
  Dir.glob("gems/*/lib", base: root).sort.each { |path| add_load_path(path) }
end

def test_paths
  Dir.glob("gems/*/test/**/*.rb", base: root).sort
end
