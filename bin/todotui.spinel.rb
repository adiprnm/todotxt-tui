#!/usr/bin/env ruby
# frozen_string_literal: true

# Spinel AOT entry point.
#
# Bundler itself cannot be compiled, so the load paths are passed on the
# command line instead:
#
#   spinel bin/todotui.spinel.rb -o tt -I lib -I /path/to/ruby-tui/lib
#
# The produced binary is standalone (no Ruby, no Bundler at runtime).

require 'todotui'

Todotui::CLI.run(ARGV)
