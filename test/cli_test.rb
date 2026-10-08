# frozen_string_literal: true

require_relative 'test_helper'
require 'pty'
require 'timeout'

class CliTest < Minitest::Test
  include TestHelpers

  def test_parse_reads_flags
    options = Todotui::CLI.parse(
      ['--snapshot', '--demo', '--file=/tmp/x.txt', '--config=/tmp/cfg',
       '--theme=plain', '--w=80', '--h=24']
    )

    assert_equal true, options[:snapshot]
    assert_equal true, options[:demo]
    assert_equal '/tmp/x.txt', options[:file]
    assert_equal '/tmp/cfg', options[:config]
    assert_equal 'plain', options[:theme]
    assert_equal 80, options[:w]
    assert_equal 24, options[:h]
  end

  def test_snapshot_prints_a_frame
    Dir.mktmpdir('todotui') do |dir|
      app = app_with(dir, ['hello from the file +demo'])
      out, = capture_io { Todotui::CLI.snapshot(app, w: 80, h: 24) }
      text = plain(out)

      assert_includes text, 'todotui'
      assert_includes text, 'hello from the'
    end
  end

  def test_a_task_can_be_typed_through_a_real_terminal
    Dir.mktmpdir('todotui') do |dir|
      file = File.join(dir, 'todo.txt')
      config = File.join(dir, 'config')
      root = File.expand_path('..', __dir__)
      script = File.join(root, 'bin', 'todotui')

      out = +''
      status = nil
      PTY.spawn(RbConfig.ruby, script, "--file=#{file}", "--config=#{config}") do |reader, writer, pid|
        drain = Thread.new do
          loop { out << reader.readpartial(65_536) }
        rescue EOFError, Errno::EIO
        end

        sleep 1.2
        ['a', 'p', 'i', 'n', 'g', ' ', 'h', 'o', 'm', 'e', "\r", 'q'].each do |key|
          writer.print(key)
          writer.flush
          sleep 0.2
        end

        begin
          Timeout.timeout(10) { _, status = Process.wait2(pid) }
        rescue Timeout::Error
          Process.kill('KILL', pid)
          status = nil
        end
        drain.join(1)
      end

      assert status && status.success?, "todotui must exit cleanly (got #{status.inspect})"
      assert_includes out, TUI::Term::ALT_ON
      assert_includes out, TUI::Term::ALT_OFF
      assert File.file?(file), 'the task was written to todo.txt'
      assert_includes File.read(file), 'ping home'
      refute_includes plain(out), 'pingping', 'keys are not echoed'
    end
  end

  def test_the_help_key_lists_bindings_in_a_real_terminal
    Dir.mktmpdir('todotui') do |dir|
      file = File.join(dir, 'todo.txt')
      config = File.join(dir, 'config')
      root = File.expand_path('..', __dir__)
      script = File.join(root, 'bin', 'todotui')

      out = +''
      status = nil
      PTY.spawn(RbConfig.ruby, script, "--file=#{file}", "--config=#{config}") do |reader, writer, pid|
        drain = Thread.new do
          loop { out << reader.readpartial(65_536) }
        rescue EOFError, Errno::EIO
        end

        sleep 1.2
        writer.print('?')
        writer.flush
        sleep 0.8
        writer.print('q')
        writer.flush

        begin
          Timeout.timeout(10) { _, status = Process.wait2(pid) }
        rescue Timeout::Error
          Process.kill('KILL', pid)
          status = nil
        end
        drain.join(1)
      end

      assert status && status.success?, "todotui must exit cleanly (got #{status.inspect})"
      text = plain(out)
      assert_includes text, 'add a task'
      assert_includes text, 'archive completed tasks'
    end
  end
end
