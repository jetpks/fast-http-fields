# frozen_string_literal: true

source "https://rubygems.org"

# Monorepo: every directory under gems/ is a path gem via its gemspec
# (glob-driven — a new gem directory needs no Gemfile edit; the four
# later gems arrive this way). The ROOT Gemfile is the bundle entry
# point; config/sus.rb routes the test run across every gem.
Dir.glob("gems/*").sort.each { |dir| gemspec path: dir }

group :development, :test do
  gem "covered"
  gem "rubocop"
  gem "sus"
end
