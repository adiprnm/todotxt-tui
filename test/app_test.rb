# frozen_string_literal: true

require_relative 'test_helper'

class AppTest < Minitest::Test
  include TestHelpers

  SAMPLE = [
    '(A) 2024-04-01 Pay the bill +home due:2024-04-10',
    'Buy milk and eggs +errands @market',
    'x 2024-04-05 2024-04-01 Call mom +family @phone'
  ].freeze

  def test_loads_a_file_and_shows_its_tasks
    Dir.mktmpdir('todotui') do |dir|
      app = app_with(dir, SAMPLE)
      text = screen_text(app.root)

      assert_includes text, 'todotui'
      assert_includes text, 'Pay the bill'
      assert_includes text, '2 open · 1 done'
      assert_equal 2, app.tasks.length - 1, 'the completed task is loaded too'
    end
  end

  def test_adding_a_task_writes_it_to_the_file
    Dir.mktmpdir('todotui') do |dir|
      app = app_with(dir)
      app.save_task(priority: 'a', body: 'Write the docs +work', due: '2024-12-31')

      line = File.read(File.join(dir, 'todo.txt')).strip
      assert_equal "(A) #{Date.today} Write the docs +work due:2024-12-31", line
      assert_equal 1, app.tasks.length
    end
  end

  def test_editing_a_task_keeps_its_creation_date
    Dir.mktmpdir('todotui') do |dir|
      app = app_with(dir, ['2024-01-01 Old title'])
      task = app.tasks.first
      app.open_editor(task)
      app.save_task(priority: 'B', body: 'New title +x', due: '')

      assert_equal '2024-01-01', app.tasks.first.creation_date
      assert_equal '(B) 2024-01-01 New title +x', File.read(File.join(dir, 'todo.txt')).strip
    end
  end

  def test_toggling_completes_and_reopens_a_task
    Dir.mktmpdir('todotui') do |dir|
      app = app_with(dir, ['(A) Call mom'])
      app.toggle_selected

      assert app.tasks.first.completed
      assert_equal Date.today.to_s, app.tasks.first.completion_date
      assert_equal 'A', app.tasks.first.priority, 'the priority survives completion'
      assert_match(/^x #{Date.today} \(A\) Call mom/, File.read(File.join(dir, 'todo.txt')))

      app.toggle_selected                     # scope is Open, so reselect
      app.instance_variable_get(:@scope_radio).select(2) # Done
      app.toggle_selected
      task = app.tasks.first
      assert_equal false, task.completed
      assert_nil task.completion_date
    end
  end

  def test_delete_and_undo
    Dir.mktmpdir('todotui') do |dir|
      app = app_with(dir, ['one', 'two'])
      removed = app.selected_task
      app.delete_selected

      assert_equal 1, app.tasks.length
      refute_includes File.read(File.join(dir, 'todo.txt')), removed.summary

      app.undo_delete
      assert_equal 2, app.tasks.length
      assert_includes File.read(File.join(dir, 'todo.txt')), removed.summary
    end
  end

  def test_archiving_moves_completed_tasks_out
    Dir.mktmpdir('todotui') do |dir|
      app = app_with(dir, ['open one', 'x 2024-04-01 done two'])
      app.archive_done

      assert_equal 1, app.tasks.length
      assert_equal 'open one', app.tasks.first.to_s
      assert_includes File.read(File.join(dir, 'done.txt')), 'done two'
    end
  end

  def test_settings_change_the_file_and_persist_it
    Dir.mktmpdir('todotui') do |dir|
      app = app_with(dir, ['first file'])
      other = File.join(dir, 'elsewhere', 'work.txt')
      FileUtils.mkdir_p(File.dirname(other))
      File.write(other, "from the other file\n")

      app.open_settings
      assert app.overlay_shown?
      app.save_settings(todo_file: other)

      refute app.overlay_shown?
      assert_equal other, app.file_path
      assert_equal ['from the other file'], app.tasks.map(&:to_s)

      config_text = File.read(app.config.path)
      assert_includes config_text, "todo_file=#{other}"
    end
  end

  def test_filtering_by_text_and_scope
    Dir.mktmpdir('todotui') do |dir|
      app = app_with(dir, SAMPLE)

      app.instance_variable_get(:@search).value = '+home'
      assert_equal 1, app.instance_variable_get(:@table).rows.length

      app.instance_variable_get(:@search).value = ''
      app.instance_variable_get(:@scope_radio).select(2) # Done
      assert_equal 1, app.instance_variable_get(:@table).rows.length

      app.instance_variable_get(:@scope_radio).select(0) # All
      assert_equal 3, app.instance_variable_get(:@table).rows.length
    end
  end

  def test_overdue_tasks_are_flagged
    Dir.mktmpdir('todotui') do |dir|
      app = app_with(dir, ["late due:#{Date.today - 3}", "soon due:#{Date.today + 3}"])

      assert app.tasks.find { |t| t.overdue? }
      text = screen_text(app.root)
      assert_includes text, '!'
      assert_includes (app.instance_variable_get(:@details).values.map(&:text).join(' ')), 'overdue'
    end
  end

  def test_the_editor_preview_shows_the_resulting_line
    Dir.mktmpdir('todotui') do |dir|
      app = app_with(dir)
      app.open_editor
      app.instance_variable_get(:@f_priority).editor.value = 'A'
      app.instance_variable_get(:@f_body).editor.value = 'Preview me'
      app.instance_variable_get(:@f_due).editor.value = '2030-01-01'
      app.send(:refresh_preview)

      preview = app.instance_variable_get(:@preview).text
      assert_includes preview, '(A)'
      assert_includes preview, 'Preview me'
      assert_includes preview, 'due:2030-01-01'
    end
  end

  def test_apply_due_adds_replaces_and_removes_the_token
    Dir.mktmpdir('todotui') do |dir|
      app = app_with(dir)

      assert_equal 'task due:2030-01-01', app.apply_due('task', '2030-01-01')
      assert_equal 'task due:2031-02-02', app.apply_due('task due:2030-01-01', '2031-02-02')
      assert_equal 'task', app.apply_due('task due:2030-01-01', '')
    end
  end

  def test_the_frame_fits_every_size
    Dir.mktmpdir('todotui') do |dir|
      app = app_with(dir, SAMPLE)
      [[60, 16], [80, 24], [100, 30], [160, 40]].each do |cols, rows|
        lines = screen_lines(app.root, cols, rows)
        assert_equal rows, lines.length, "height at #{cols}x#{rows}"
        lines.each_with_index do |line, i|
          assert_equal cols, line.length, "row #{i} at #{cols}x#{rows}: #{line.inspect}"
        end
      end
    end
  end

  def test_narrow_terminals_drop_the_meta_column
    Dir.mktmpdir('todotui') do |dir|
      app = app_with(dir, SAMPLE)
      app.resize(60, 16)
      refute_includes app.instance_variable_get(:@table).columns.map(&:key), :meta

      app.resize(120, 30)
      assert_includes app.instance_variable_get(:@table).columns.map(&:key), :meta
    end
  end

  def test_a_modal_keeps_the_focus_inside_itself
    Dir.mktmpdir('todotui') do |dir|
      app = app_with(dir, SAMPLE)
      ui = TUI::App.new(app.root, out: StringIO.new, size: [100, 30])
      app.attach(ui)
      app.open_editor

      reachable = ui.focusables
      assert reachable.length.positive?
      refute_includes reachable, app.instance_variable_get(:@table),
                      'the list behind the modal cannot take the focus'
    end
  end

  def test_archiving_uses_the_configured_done_file
    Dir.mktmpdir('todotui') do |dir|
      file = File.join(dir, 'todo.txt')
      File.write(file, "open one\nx 2024-04-01 done two\n")
      done = File.join(dir, 'archive', 'finished.txt')
      config = Todotui::Config.new(path: File.join(dir, 'config'))
      config.done_file = done
      app = Todotui::App.new(config: config, file: file)

      app.archive_done

      assert_equal done, app.store.done_path
      assert_includes File.read(done), 'done two'
      refute File.exist?(File.join(dir, 'done.txt')), 'no sibling archive is written'
    end
  end

  def test_settings_save_the_done_file
    Dir.mktmpdir('todotui') do |dir|
      app = app_with(dir)
      other_done = File.join(dir, 'archive', 'finished.txt')
      app.open_settings
      app.save_settings(todo_file: app.file_path, done_file: other_done)

      assert_equal other_done, app.store.done_path
      assert_includes File.read(app.config.path), "done_file=#{other_done}"
    end
  end

  def test_every_priority_gets_a_distinct_colour
    colors = ('A'..'Z').map { |letter| Todotui::TaskTable.priority_style(letter) }

    assert_equal 26, colors.uniq.length
    assert_equal :text, Todotui::TaskTable.priority_style(nil)
  end

  def test_the_priority_colour_tints_the_whole_row
    Dir.mktmpdir('todotui') do |dir|
      app = app_with(dir, ['(A) first task', '(B) second task'])
      ui = TUI::App.new(app.root, out: StringIO.new, size: [100, 30])
      app.attach(ui)
      app.resize(100, 30)
      line = ui.render_lines.find { |l| l.include?('second task') }

      color = Todotui::TaskTable.priority_style('B')
      assert_includes line, "#{color}(B)", 'the priority badge is tinted'
      assert_includes line, "#{color}second task", 'the task text is tinted too'
    end
  end
end
