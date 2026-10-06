# frozen_string_literal: true

# A plain runnable script as well: ruby todotui.rb [options]

root = File.dirname(File.realpath(__FILE__))
ENV['BUNDLE_GEMFILE'] ||= File.join(root, 'Gemfile')
require 'bundler/setup'

$LOAD_PATH.unshift(File.join(root, 'lib'))
require 'todotui'

Todotui::CLI.run(ARGV)
