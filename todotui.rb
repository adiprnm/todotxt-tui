# frozen_string_literal: true

# A plain runnable script as well: ruby todotui.rb [options]

ENV['BUNDLE_GEMFILE'] ||= File.expand_path('Gemfile', __dir__)
require 'bundler/setup'

$LOAD_PATH.unshift(File.expand_path('lib', __dir__))
require 'todotui'

Todotui::CLI.run(ARGV)
