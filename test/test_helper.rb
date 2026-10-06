# frozen_string_literal: true

ENV['BUNDLE_GEMFILE'] ||= File.expand_path('../Gemfile', __dir__)
require 'bundler/setup'

require 'minitest/autorun'
require 'stringio'
require 'tmpdir'
require 'date'

$LOAD_PATH.unshift(File.expand_path('../lib', __dir__))
require 'todotui'
require 'ruby-tui'

module TestHelpers
  # Drop SGR escape sequences so assertions read the text of a frame.
  def plain(str)
    str.gsub(/\e\[[0-9;?]*[a-zA-Z]/, '')
  end

  # One off-screen frame as an array of colourless rows.
  def screen_lines(root, cols = 100, rows = 30)
    TUI::App.new(root, out: StringIO.new, size: [cols, rows])
       .render_lines.map { |line| plain(line) }
  end

  def screen_text(root, cols = 100, rows = 30)
    screen_lines(root, cols, rows).join("\n")
  end

  # A store-backed app inside a throwaway directory.
  def app_with(dir, lines = [])
    file = File.join(dir, 'todo.txt')
    File.write(file, lines.empty? ? '' : "#{lines.join("\n")}\n")
    config = Todotui::Config.new(path: File.join(dir, 'config'))
    Todotui::App.new(config: config, file: file)
  end
end
