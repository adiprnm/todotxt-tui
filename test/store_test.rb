# frozen_string_literal: true

require_relative 'test_helper'

class StoreTest < Minitest::Test
  include TestHelpers

  def test_load_and_save_round_trip
    Dir.mktmpdir('todotui') do |dir|
      path = File.join(dir, 'nested', 'todo.txt')
      store = Todotui::Store.new(path)

      assert_equal [], store.load, 'a missing file is an empty list'

      tasks = [
        Todotui::Task.new(priority: 'A', body: 'Call mom +family'),
        Todotui::Task.new(completed: true, completion_date: '2024-05-01',
                          body: 'Ship it +work')
      ]
      store.save(tasks)

      assert store.exist?
      reloaded = store.load
      assert_equal tasks.map(&:to_s), reloaded.map(&:to_s)
    end
  end

  def test_saving_nothing_leaves_an_empty_file
    Dir.mktmpdir('todotui') do |dir|
      store = Todotui::Store.new(File.join(dir, 'todo.txt'))
      store.save([])

      assert_equal '', File.read(store.path)
      assert_equal [], store.load
    end
  end

  def test_archive_appends_completed_tasks_to_done_txt
    Dir.mktmpdir('todotui') do |dir|
      store = Todotui::Store.new(File.join(dir, 'todo.txt'))
      tasks = [
        Todotui::Task.new(body: 'Open one'),
        Todotui::Task.new(completed: true, completion_date: '2024-05-01', body: 'Done one'),
        Todotui::Task.new(completed: true, completion_date: '2024-05-02', body: 'Done two')
      ]

      assert_equal 2, store.archive(tasks)
      done = File.read(File.join(dir, 'done.txt'))
      assert_includes done, 'Done one'
      assert_includes done, 'Done two'
      refute_includes done, 'Open one'
    end
  end

  def test_archive_writes_to_a_configured_done_file
    Dir.mktmpdir('todotui') do |dir|
      done_path = File.join(dir, 'archive', 'finished.txt')
      store = Todotui::Store.new(File.join(dir, 'todo.txt'), done_path: done_path)
      assert_equal done_path, store.done_path

      store.archive([Todotui::Task.new(completed: true, completion_date: '2024-05-01',
                                       body: 'Done one')])

      assert_includes File.read(done_path), 'Done one'
      refute File.exist?(File.join(dir, 'done.txt')), 'the sibling file is not touched'
    end
  end
end

class ConfigTest < Minitest::Test
  include TestHelpers

  ENV_KEYS = (Todotui::Config::ENV_KEYS + Todotui::Config::DONE_ENV_KEYS).freeze

  def with_clean_env
    saved = ENV_KEYS.to_h { |key| [key, ENV[key]] }
    ENV_KEYS.each { |key| ENV.delete(key) }
    yield
  ensure
    saved.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
  end

  def test_saves_and_reloads_the_todo_file
    Dir.mktmpdir('todotui') do |dir|
      config = Todotui::Config.new(path: File.join(dir, 'config'))
      config.todo_file = File.join(dir, 'work.txt')
      config.save

      reloaded = Todotui::Config.new(path: File.join(dir, 'config'))
      assert_equal File.join(dir, 'work.txt'), reloaded.todo_file
    end
  end

  def test_saves_and_reloads_the_done_file
    Dir.mktmpdir('todotui') do |dir|
      config = Todotui::Config.new(path: File.join(dir, 'config'))
      config.todo_file = File.join(dir, 'work.txt')
      config.done_file = File.join(dir, 'archive', 'finished.txt')
      config.save

      reloaded = Todotui::Config.new(path: File.join(dir, 'config'))
      assert_equal File.join(dir, 'archive', 'finished.txt'), reloaded.done_file
      assert_equal reloaded.done_file, reloaded.resolve_done
    end
  end

  def test_saves_and_reloads_the_filter
    Dir.mktmpdir('todotui') do |dir|
      config = Todotui::Config.new(path: File.join(dir, 'config'))
      assert_equal '', config.filter
      assert_equal 'Open', config.scope

      config.filter = '+work @laptop'
      config.scope = 'Done'
      config.save

      reloaded = Todotui::Config.new(path: File.join(dir, 'config'))
      assert_equal '+work @laptop', reloaded.filter
      assert_equal 'Done', reloaded.scope
    end
  end

  def test_resolve_done_defaults_to_done_txt_next_to_todo
    Dir.mktmpdir('todotui') do |dir|
      config = Todotui::Config.new(path: File.join(dir, 'config'))
      todo = File.join(dir, 'work', 'todo.txt')

      with_clean_env do
        assert_equal File.join(dir, 'work', 'done.txt'), config.resolve_done(todo: todo)
        assert_equal File.join(dir, 'explicit-done.txt'),
                     config.resolve_done(File.join(dir, 'explicit-done.txt'), todo: todo)

        ENV['TODOTXT_DONE_FILE'] = File.join(dir, 'env-done.txt')
        assert_equal File.join(dir, 'env-done.txt'), config.resolve_done(todo: todo)
      end
    end
  end

  def test_resolve_precedence
    Dir.mktmpdir('todotui') do |dir|
      config = Todotui::Config.new(path: File.join(dir, 'config'))
      config.todo_file = File.join(dir, 'from-config.txt')

      with_clean_env do
        assert_equal File.join(dir, 'from-config.txt'), config.resolve
        assert_equal File.join(dir, 'explicit.txt'),
                     config.resolve(File.join(dir, 'explicit.txt'))

        ENV['TODOTXT_FILE'] = File.join(dir, 'from-env.txt')
        assert_equal File.join(dir, 'from-env.txt'), config.resolve
        assert_equal File.join(dir, 'explicit.txt'),
                     config.resolve(File.join(dir, 'explicit.txt'))
      end
    end
  end

  def test_generic_todo_file_env_is_ignored
    Dir.mktmpdir('todotui') do |dir|
      config = Todotui::Config.new(path: File.join(dir, 'config'))
      config.todo_file = File.join(dir, 'from-config.txt')
      saved = ENV['TODO_FILE']
      ENV['TODO_FILE'] = File.join(dir, 'from-generic-env.txt')

      assert_equal File.join(dir, 'from-config.txt'), config.resolve,
                   'a generic TODO_FILE must not override the config'
    ensure
      saved.nil? ? ENV.delete('TODO_FILE') : ENV['TODO_FILE'] = saved
    end
  end

  def test_defaults
    assert_equal File.join(Dir.home, 'todo.txt'), Todotui::Config.default_todo_file
    assert_equal File.join(Dir.home, 'done.txt'), Todotui::Config.default_done_file
    assert_equal 'todo.txt', Todotui::Config::FILENAME
    assert_equal 'done.txt', Todotui::Config::DONE_FILENAME
  end
end
