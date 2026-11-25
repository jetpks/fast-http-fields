# frozen_string_literal: true

require "fast/sfv"

# The docs gates: the diataxis tree under docs/ is complete and non-empty,
# every fenced ruby example in the README and the docs tree executes and
# answers its documented output (or raises its documented error class),
# every fenced block carries a language tag, and every relative link in
# the scoped markdown resolves. File-local checks plus example execution
# only: no network, no gem installation. Shell fences are not executed;
# Gemfile lines are inline code, never fenced ruby (the convention the
# executor enforces by executing everything it does execute).

# A fence: language tag, body lines, and the 1-based line number of the
# first body line (fences are column 0, the family convention).
SFV_DOCS_FENCE = Struct.new(:path, :lang, :lines, :start_line)

# `CODE # => EXPECTED` — EXPECTED is Ruby source, evaluated in the same
# context, compared with ==. `CODE # raises SomeError` — the code must
# raise that class. Trailing prose on assertion lines is not supported:
# the expected part runs to end of line.
SFV_DOCS_ASSERTION = /\A(?<code>.+?)\s+#\s+=>\s+(?<expected>.+?)\s*\z/
SFV_DOCS_RAISES = /\A(?<code>.+?)\s+#\s+raises\s+(?<klass>[A-Z][A-Za-z0-9:_]*)\s*\z/

describe "fast-sfv docs" do
  def gem_root
    File.expand_path("../../..", __dir__)
  end

  def scoped_files
    [File.join(gem_root, "README.md")] + Dir.glob(File.join(gem_root, "docs", "**", "*.md")).sort
  end

  def fences(path)
    source = File.readlines(path, chomp: true)
    out = []
    lang = nil
    body = nil
    start = nil
    source.each_with_index do |line, index|
      if lang.nil?
        if (m = line.match(/\A```(?<l>[A-Za-z0-9_-]*)\s*\z/))
          lang = m[:l]
          body = []
          start = index + 2
        end
      elsif line.start_with?("```")
        out << SFV_DOCS_FENCE.new(path, lang, body, start)
        lang = nil
        body = nil
      else
        body << line
      end
    end
    out
  end

  def docs_assert(actual, expected, location)
    return if actual == expected

    raise "DOCS_EXAMPLE_FAIL #{location}: documented #{expected.inspect}, got #{actual.inspect}"
  end

  def docs_raises(block, klass_name, location)
    klass = Object.const_get(klass_name)
    block.call
    raise "DOCS_EXAMPLE_FAIL #{location}: documented raise of #{klass_name}, nothing raised"
  rescue klass
    nil
  end

  def run_fence(fence)
    rewritten = fence.lines.each_with_index.map do |line, index|
      location = "#{fence.path}:#{fence.start_line + index}"
      if (m = line.match(SFV_DOCS_ASSERTION))
        "docs_assert((#{m[:code]}), (#{m[:expected]}), #{location.inspect})"
      elsif (m = line.match(SFV_DOCS_RAISES))
        "docs_raises(-> { (#{m[:code]}) }, #{m[:klass].inspect}, #{location.inspect})"
      else
        line
      end
    end
    instance_eval(rewritten.join("\n"), fence.path, fence.start_line)
  end

  # Lines outside ``` fences (the fast-llm docs_links pattern).
  def prose_sections(lines)
    fence = nil
    lines.filter_map do |line|
      if fence
        fence = nil if line.start_with?(fence)
        next nil
      end
      if (m = line.match(/\A\s*(```|~~~)/))
        fence = m[1]
        next nil
      end
      line
    end
  end

  # Reference definitions (label => target) and inline-link targets.
  def link_inventory(path)
    definitions = {}
    inline = []
    prose_sections(File.readlines(path, chomp: true)).each do |line|
      if (m = line.match(/\A {0,3}\[([^\]]+)\]:\s*(\S+)/))
        definitions[m[1]] = m[2]
      else
        line.scan(/\[[^\]]*\]\(([^)]+)\)/) { |(target)| inline << target }
      end
    end
    [definitions, inline]
  end

  def used_labels(path)
    labels = []
    prose_sections(File.readlines(path, chomp: true)).each do |line|
      next if line.match?(/\A {0,3}\[([^\]]+)\]:\s*(\S+)/)

      stripped = line.gsub(/\[[^\]]*\]\([^)]*\)/, "")
      stripped.scan(/\[([^\]]+)\]/) { |(label)| labels << label }
    end
    labels
  end

  # A relative target resolves when the file (or directory) exists next to
  # the linking file; anchors are stripped; http(s) URLs pass.
  def resolves?(path, target)
    bare = target.sub(/\A</, "").sub(/>\z/, "").sub(/#.*\z/, "")
    return true if bare.empty?
    return true if %r{\Ahttps?://}.match?(bare)

    File.exist?(File.expand_path(bare, File.dirname(path)))
  end

  it "has the four diataxis quadrants, each non-empty" do
    %w[tutorials how-to-guides reference explanation].each do |quadrant|
      pages = Dir.glob(File.join(gem_root, "docs", quadrant, "*.md"))
      expect(pages).not.to be(:empty?)
      expect(pages.size).to be(:>=, 1)
    end
  end

  it "tags every fenced code block with a language" do
    untagged = []
    scoped_files.each do |path|
      fences(path).each do |fence|
        untagged << "#{path} line #{fence.start_line - 1}" if fence.lang.empty?
      end
    end
    expect(untagged).to be(:empty?)
  end

  it "executes every fenced ruby example and checks every documented output" do
    executed = 0
    assertions = 0
    failures = []
    scoped_files.each do |path|
      fences(path).each do |fence|
        next unless fence.lang == "ruby"

        executed += 1
        assertions += fence.lines.count { |l| l.match?(SFV_DOCS_ASSERTION) || l.match?(SFV_DOCS_RAISES) }
        begin
          run_fence(fence)
        rescue StandardError, SyntaxError => e
          failures << "#{path} fence at line #{fence.start_line}: #{e.class}: #{e.message}"
        end
      end
    end

    expect(scoped_files.size).to be(:>=, 11)
    expect(executed).to be(:>=, 20)
    expect(assertions).to be(:>=, 40)
    expect(failures).to be(:empty?)
  end

  it "resolves every link in the scoped markdown" do
    broken = []
    scoped_files.each do |path|
      definitions, inline = link_inventory(path)
      (definitions.values + inline).each do |target|
        next if resolves?(path, target)

        broken << "#{path}: #{target}"
      end
    end
    expect(broken).to be(:empty?)
  end

  it "closes every used reference label over its same-file definitions" do
    dangling = []
    scoped_files.each do |path|
      definitions, = link_inventory(path)
      used_labels(path).each do |label|
        next if definitions.key?(label)

        dangling << "#{path}: [#{label}]"
      end
    end
    expect(dangling).to be(:empty?)
  end

  it "links the README into the docs tree" do
    definitions, inline = link_inventory(File.join(gem_root, "README.md"))
    targets = (definitions.values + inline).map { |t| t.sub(/\A</, "").sub(/>\z/, "").sub(/#.*\z/, "") }
    docs_targets = targets.select { |t| t.include?("docs/") }
    expect(docs_targets.size).to be(:>=, 4)
    expect(docs_targets).to be(:include?, "docs/tutorials/getting-started.md")
  end
end
