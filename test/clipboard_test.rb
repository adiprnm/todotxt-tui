# frozen_string_literal: true

require_relative 'test_helper'
require 'fileutils'

class ClipboardTest < Minitest::Test
  include TestHelpers

  def test_prefers_wl_copy_on_wayland
    Dir.mktmpdir('clip') do |dir|
      tool(dir, 'pbcopy')
      tool(dir, 'xclip')
      tool(dir, 'wl-copy')

      with_path(dir) do
        assert_equal 'wl-copy', Todotui::Clipboard.command
      end
    end
  end

  def test_falls_back_to_x11_and_macos_tools
    Dir.mktmpdir('clip') do |dir|
      tool(dir, 'xsel')
      with_path(dir) { assert_equal 'xsel --clipboard --input', Todotui::Clipboard.command }

      FileUtils.rm(File.join(dir, 'xsel'))
      tool(dir, 'xclip')
      with_path(dir) { assert_equal 'xclip -selection clipboard', Todotui::Clipboard.command }
    end
  end

  def test_no_tool_on_path_means_no_copy
    Dir.mktmpdir('clip') do |dir|
      with_path(dir) do
        assert_nil Todotui::Clipboard.command
        assert_nil Todotui::Clipboard.copy('hello')
      end
    end
  end

  def test_copy_feeds_the_text_through_stdin
    Dir.mktmpdir('clip') do |dir|
      sink = File.join(dir, 'clip.txt')
      tool(dir, 'wl-copy', "#!/bin/sh\ncat > #{sink}\n")

      argv = nil
      with_path(dir, ENV['PATH']) { argv = Todotui::Clipboard.copy('Buy milk +errands') }

      assert_equal 'wl-copy', argv
      assert_equal 'Buy milk +errands', File.read(sink)
    end
  end

  def test_copy_quotes_shell_metacharacters
    Dir.mktmpdir('clip') do |dir|
      sink = File.join(dir, 'clip.txt')
      tool(dir, 'wl-copy', "#!/bin/sh\ncat > #{sink}\n")
      text = "it's $HOME `x`; rm -rf /"

      with_path(dir, ENV['PATH']) { Todotui::Clipboard.copy(text) }

      assert_equal text, File.read(sink)
    end
  end

  def test_a_broken_tool_is_skipped_for_the_next
    Dir.mktmpdir('clip') do |dir|
      sink = File.join(dir, 'clip.txt')
      tool(dir, 'wl-copy', "#!/bin/sh\nexit 1\n")
      tool(dir, 'xclip', "#!/bin/sh\ncat > #{sink}\n")

      argv = nil
      with_path(dir, ENV['PATH']) { argv = Todotui::Clipboard.copy('still copied') }

      assert_equal 'xclip -selection clipboard', argv
      assert_equal 'still copied', File.read(sink)
    end
  end

  private

  def with_path(*dirs)
    original = ENV['PATH']
    ENV['PATH'] = dirs.join(File::PATH_SEPARATOR)
    yield
  ensure
    ENV['PATH'] = original
  end

  def tool(dir, name, body = "#!/bin/sh\nexit 0\n")
    path = File.join(dir, name)
    File.write(path, body)
    File.chmod(0o755, path)
  end
end
