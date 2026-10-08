# frozen_string_literal: true

require 'ruby-tui'

require_relative 'task'
require_relative 'store'
require_relative 'config'
require_relative 'query'
require_relative 'table'
require_relative 'rich_label'
require_relative 'field_row'
require_relative 'source_view'

module Todotui
  # The application widget tree and its behaviour. All of the todo.txt
  # rules live in Task/Store/Query; this file only wires them to widgets.
  class App
    SCOPE_OPTIONS = %w[All Open Done].freeze

    SORT_MODES = [
      [:smart,     'smart'],
      [:due,       'due'],
      [:priority,  'priority'],
      [:alpha,     'a-z'],
      [:created,   'created'],
      [:completed, 'completed']
    ].freeze

    # How long a flash message stays before the key hint returns.
    FLASH_SECONDS = 4.0

    # The status row shows a live key hint, which a flash message replaces
    # for a few seconds (see #flash / #expire_flash).
    HINTS = {
      status:   'a add   space done   d delete   y copy   u undo   / filter   ? help   q quit',
      editor:   'enter save   tab next   esc cancel',
      settings: 'enter save   esc cancel',
      help:     'esc or ? to close'
    }.freeze

    # Panes in @dialogs, in the order they are added.
    EDITOR_PANE   = 0
    SETTINGS_PANE = 1
    HELP_PANE     = 2

    attr_reader :root, :tasks, :config, :store

    # Injectable so a test can capture the copied text without a desktop
    # clipboard; production always uses Todotui::Clipboard.
    attr_accessor :clipboard

    def initialize(config: Config.new, file: nil, done_file: nil)
      @config = config
      @clipboard = Clipboard
      todo = @config.resolve(file)
      @store = Store.new(todo, done_path: @config.resolve_done(done_file, todo: todo))
      @tasks = []

      @filter = ''
      @scope = 'Open'
      @sort_index = 0
      @undo = nil
      @editing = nil
      @demo = false
      @flash_until = nil

      build_ui
      flash("Loaded #{@tasks.length} task(s) from #{@store.path}") if reload_tasks
      refresh
    end

    # Hand the app its runtime, so modal dialogs can move the focus.
    def attach(ui)
      @ui = ui
      self
    end

    # ----------------------------------------------------------------- state

    def overlay_shown?
      @overlay.shown?
    end

    def selected_task
      row = @table.selected_row
      row && row[:task]
    end

    def file_path
      @store.path
    end

    # ------------------------------------------------------------------ UI

    def build_ui
      # Note: no footer. ruby-tui's border label draws the footer on the top
      # edge, next to the title, so the key hint lives in the status row.
      @root = TUI::Layout::Box.new(title: ' todotui ', title_right_style: :brand_path)

      body = TUI::Layout::Stack.new(direction: :vertical)
      body.add(build_toolbar, size: TUI.fixed(1))
      body.add(build_columns, size: TUI.flex(1))
      body.add(build_status, size: TUI.fixed(1))

      @dialogs = TUI::Panes.new
      @dialogs.add(build_editor)
      @dialogs.add(build_settings)
      @dialogs.add(build_help)

      @overlay = TUI::Layout::Overlay.new(body, @dialogs)
      @overlay.hide
      @root.add(@overlay)
    end

    def build_toolbar
      row = TUI::Layout::Stack.new(direction: :horizontal, gap: 1)
      row.add(TUI::Label.new('Filter', style: :label), size: TUI.fixed(6))

      @search = TUI::Input.new(placeholder: 'text, +project, @context…', padding: 1)
      @search.on(TUI::Events::CHANGE) do
        @filter = @search.value
        refresh_tasks
      end
      row.add(@search, size: TUI.flex(1))

      @scope_radio = TUI::RadioGroup.new(options: SCOPE_OPTIONS, selected: 1,
                                         orientation: :horizontal)
      @scope_radio.on(TUI::Events::CHANGE) do |value|
        @scope = value
        refresh_tasks
      end
      row.add(@scope_radio, size: TUI.auto)
      row
    end

    def build_columns
      columns = TUI::Layout::Stack.new(direction: :horizontal)

      @table_box = TUI::Layout::Box.new(title: 'Tasks')
      @table = TaskTable.new(columns: columns_for(120))
      @table.on(TUI::Events::CHANGE) { |row, _i| show_details(row && row[:task]) }
      @table.on(TUI::Events::SELECT) { |row, _i| open_editor(row[:task]) if row }
      @table_box.add(@table)

      columns.add(@table_box, size: TUI.flex(1))
      columns.add(build_details, size: TUI.percent(0.34))
      columns
    end

    # The TASK cell holds the bare task name (tags stripped); the `+ / @`
    # column keeps the projects and contexts visible, and the DUE column the
    # due date. The meta column is the first to go when the terminal is
    # narrow; the details panel still shows it.
    def columns_for(width)
      columns = [
        { key: :flag, header: '',    width: 2 },
        { key: :done, header: '',    width: 2 },
        { key: :pri,  header: 'P',   width: 3, align: :center },
        { key: :due,  header: 'DUE', width: 12 },
        { key: :text, header: 'TASK', width: TUI.flex(1) }
      ]
      columns << { key: :meta, header: '+ / @', width: 22 } if width.to_i >= 92
      columns
    end

    # Called whenever the terminal size changes (and once at startup), so the
    # table can adapt to the room it has.
    def resize(cols, _rows = nil)
      @table.set_columns(columns_for(cols))
      refresh_tasks
      self
    end

    def build_details
      @details_box = TUI::Layout::Box.new(title: 'Details')
      stack = TUI::Layout::Stack.new(direction: :vertical)
      @details = {}

      # The hero: the task's own todo.txt line, highlighted token by token.
      # Fixed height keeps the field list below it from being pushed off.
      @source = SourceView.new('', style: :text)
      @details[:line] = @source
      stack.add(@source, size: TUI.fixed(4))
      stack.add(TUI::Label.new(''), size: TUI.fixed(1))

      fields = TUI::Layout::Stack.new(direction: :vertical)
      [['Status', :status], ['Priority', :priority], ['Created', :created],
       ['Completed', :completed], ['Due', :due], ['Projects', :projects],
       ['Contexts', :contexts], ['Meta', :meta]].each do |label, key|
        row = FieldRow.new(label, label_width: 11)
        @details[key] = row
        fields.add(row, size: TUI.auto)
      end
      stack.add(fields, size: TUI.flex(1))

      @details_box.add(stack)
      @details_box
    end

    def build_status
      row = TUI::Layout::Stack.new(direction: :horizontal, gap: 2)
      @status_label = TUI::Label.new(HINTS[:status], style: :muted)
      row.add(@status_label, size: TUI.flex(1))

      @docket = RichLabel.new([], align: :right)
      row.add(@docket, size: TUI.auto)
      row
    end

    def build_editor
      @editor_box = TUI::Layout::Box.new(title: 'New task', title_right: HINTS[:editor])
      stack = TUI::Layout::Stack.new(direction: :vertical)

      @editor_form = TUI::Form.new(label_width: 9)
      @f_body = @editor_form.text(:body, 'Task', required: true, width: 62)
      @f_priority = @editor_form.text(:priority, 'Priority', placeholder: 'A-Z',
                                      width: 8, validate: method(:validate_priority))
      @f_due = @editor_form.text(:due, 'Due', placeholder: 'YYYY-MM-DD',
                                 width: 14, validate: method(:validate_due))
      @f_body.editor.on(TUI::Events::CHANGE) { refresh_preview }
      @f_due.editor.on(TUI::Events::CHANGE) { refresh_preview }
      @editor_form.button('Save')
      @editor_form.on(TUI::Events::SUBMIT) { |values| save_task(values) }
      @editor_form.on(:invalid) { flash('Please fix the highlighted field') }

      @preview = TUI::Label.new('', style: :accent)
      @preview_hint = TUI::Label.new(
        'type +project @context due:YYYY-MM-DD straight into the task',
        style: :muted
      )

      stack.add(@editor_form, size: TUI.auto)
      stack.add(TUI::Label.new(''), size: TUI.fixed(1))
      stack.add(@preview, size: TUI.auto)
      stack.add(@preview_hint, size: TUI.fixed(1))
      @editor_box.add(stack)
      @editor_box
    end

    def build_settings
      @settings_box = TUI::Layout::Box.new(title: 'Settings', title_right: HINTS[:settings])
      stack = TUI::Layout::Stack.new(direction: :vertical)

      @settings_form = TUI::Form.new(label_width: 12)
      @f_file = @settings_form.text(:todo_file, 'todo.txt', required: true, width: 64)
      @f_done = @settings_form.text(:done_file, 'done.txt', required: true, width: 64)
      @settings_form.button('Save')
      @settings_form.on(TUI::Events::SUBMIT) { |values| save_settings(values) }

      @settings_current = TUI::Label.new('', style: :value, wrap: true)
      @settings_config = TUI::Label.new('', style: :value, wrap: true)
      @settings_saved = TUI::Label.new('', style: :value, wrap: true)
      @settings_hint = TUI::Label.new(
        'Saving writes both paths to the config, so the next launch opens them.',
        style: :muted, wrap: true
      )

      stack.add(@settings_form, size: TUI.auto)
      stack.add(TUI::Label.new(''), size: TUI.fixed(1))
      stack.add(TUI::Label.new('Current todo.txt', style: :label), size: TUI.auto)
      stack.add(@settings_current, size: TUI.auto)
      stack.add(TUI::Label.new(''), size: TUI.fixed(1))
      stack.add(TUI::Label.new('Config file', style: :label), size: TUI.auto)
      stack.add(@settings_config, size: TUI.auto)
      stack.add(TUI::Label.new('Saved paths', style: :label), size: TUI.auto)
      stack.add(@settings_saved, size: TUI.auto)
      stack.add(TUI::Label.new(''), size: TUI.fixed(1))
      stack.add(@settings_hint, size: TUI.auto)

      @settings_box.add(stack)
      @settings_box
    end

    # The full key list, one row per binding. Keys are padded so the
    # descriptions line up; RichLabel paints the key and the description in
    # different styles and measures to its natural width, so the dialog
    # stays compact in the middle of the screen.
    def build_help
      @help_box = TUI::Layout::Box.new(title: 'Keys', title_right: HINTS[:help], padding: 1)
      rows = [
        ['a',          'add a task'],
        ['space',      'complete / reopen the selected task'],
        ['enter, e',   'edit the selected task'],
        ['d',          'delete the selected task (u undoes it)'],
        ['y',          'copy the task name (no priority, tags or dates)'],
        ['u',          'undo the last delete'],
        ['j / k',      'move the selection (arrow keys work too)'],
        ['s',          'cycle the sort: smart, due, priority, a-z…'],
        ['/',          'jump to the filter'],
        [',',          'settings: where todo.txt lives'],
        ['A',          'archive completed tasks to done.txt'],
        ['?',          'show this help'],
        ['esc',        'cancel a dialog / clear the filter'],
        ['q, ctrl-c',  'quit']
      ]
      width = rows.map { |key, _desc| key.length }.max

      stack = TUI::Layout::Stack.new(direction: :vertical)
      rows.each do |key, desc|
        row = RichLabel.new([["#{key.ljust(width)}  ", :accent], [desc, :value]], gap: 0)
        stack.add(row, size: TUI.fixed(1))
      end
      @help_box.add(stack)
      @help_box
    end

    # --------------------------------------------------------------- actions

    def open_editor(task = nil)
      clear_undo
      @editing = task
      @editor_box.title = task ? 'Edit task' : 'New task'
      @f_body.editor.value = task ? task.body : ''
      @f_priority.editor.value = task ? task.priority.to_s : ''
      @f_due.editor.value = task ? task.due_date.to_s : ''
      @editor_form.fields.each { |field| field.error = nil }
      refresh_preview

      show_overlay(EDITOR_PANE)
      @ui.focus(@f_body.editor) if @ui
      self
    end

    def save_task(values)
      priority = values[:priority].to_s.strip.upcase
      body = apply_due(values[:body], values[:due])

      if @editing
        @editing.priority = priority.empty? ? nil : priority
        @editing.body = body
        flash("Updated: #{@editing.summary}")
      else
        task = Task.new(priority: priority.empty? ? nil : priority,
                        creation_date: Calendar.today, body: body)
        @tasks << task
        flash("Added: #{task.summary}")
      end

      @editing = nil
      hide_overlay
      persist
      refresh
      self
    end

    def open_settings
      clear_undo
      @f_file.editor.value = @store.path
      @f_done.editor.value = @store.done_path || @config.resolve_done(todo: @store.path)
      @settings_current.text = "#{@store.path}  |  #{@store.done_path || @config.resolve_done(todo: @store.path)}"
      @settings_config.text = @config.path
      @settings_saved.text = @config.done_file ? @config.done_file : '(done.txt next to todo.txt)'
      @settings_form.fields.each { |field| field.error = nil }

      show_overlay(SETTINGS_PANE)
      @ui.focus(@f_file.editor) if @ui
      self
    end

    def save_settings(values)
      path = File.expand_path(values[:todo_file].to_s.strip)
      done_value = values[:done_file].to_s.strip
      done = done_value.empty? ? @config.resolve_done(todo: path) : File.expand_path(done_value)

      @config.todo_file = path
      @config.done_file = done
      @config.save

      @store = Store.new(path, done_path: done)
      loaded = reload_tasks
      @filter = ''
      @search.value = ''
      @scope = 'Open'
      @scope_radio.select(1)

      hide_overlay
      flash("todo.txt is now #{path} (#{@tasks.length} task(s))") if loaded
      refresh
      self
    end

    # Toggle the key list. It has no focusable children, so the overlay
    # drops the focus and the global bindings stay live while it is up.
    def open_help
      if overlay_shown?
        hide_overlay
      else
        clear_undo
        show_overlay(HELP_PANE)
      end
      self
    end

    def cancel
      if overlay_shown?
        # Closing the help dialog needs no flash -- nothing was cancelled.
        if @dialogs.active == HELP_PANE
          hide_overlay
        else
          @editing = nil
          hide_overlay
          flash('Cancelled')
        end
      elsif @filter.to_s.empty?
        @ui.focus(@table) if @ui
      else
        @filter = ''
        @search.value = ''
        flash('Filter cleared')
      end
      self
    end

    def toggle_selected
      task = selected_task
      return flash('No task selected') unless task

      clear_undo
      task.completed = !task.completed
      task.completion_date = task.completed ? Calendar.today : nil
      persist
      refresh
      flash(task.completed ? "Completed: #{task.summary}" : "Reopened: #{task.summary}")
      self
    end

    def delete_selected
      task = selected_task
      return flash('No task selected') unless task

      index = @tasks.index { |candidate| candidate.equal?(task) }
      @tasks.delete_at(index)
      @undo = { task: task, index: index }
      persist
      refresh
      flash("Deleted: #{task.summary}  (u to undo)")
      self
    end

    # Copy the bare task name -- no priority, dates, +projects, @contexts or
    # key:value metadata -- to the system clipboard.
    def copy_selected
      task = selected_task
      return flash('No task selected') unless task

      name = task.title
      if @clipboard.copy(name)
        flash("Copied: #{name}")
      else
        flash('No clipboard tool found (install wl-copy, xclip or xsel)')
      end
      self
    end

    def undo_delete
      return flash('Nothing to undo') unless @undo

      task = @undo[:task]
      @tasks.insert(@undo[:index] || @tasks.length, task)
      @undo = nil
      persist
      refresh
      flash("Restored: #{task.summary}")
      self
    end

    def cycle_sort
      @sort_index = (@sort_index + 1) % SORT_MODES.length
      refresh_tasks
      flash("Sort: #{SORT_MODES[@sort_index].last}")
      self
    end

    def archive_done
      done = @tasks.select(&:completed)
      return flash('No completed tasks to archive') if done.empty?

      count = @store.archive(@tasks)
      @tasks -= done
      persist
      refresh
      flash("Archived #{count} task(s) to #{@store.done_path || 'done.txt'}")
      self
    end

    def move_selection(delta)
      return unless @table.rows.any?

      @table.select(@table.selected + delta)
      self
    end

    def focus_filter
      @ui.focus(@search) if @ui
      self
    end

    def focus_list
      @ui.focus(@table) if @ui
      self
    end

    # Load a handful of example tasks (never written to disk) so
    # `--snapshot --demo` has something to show. Dates are relative to
    # today so the frame always looks alive.
    def demo!
      @demo = true
      today = Calendar.today
      day = ->(offset) { Calendar.offset(offset) }
      @tasks = [
        Task.new(priority: 'A', creation_date: day.call(-9),
                 body: "Pay the electricity bill +home due:#{day.call(2)}"),
        Task.new(priority: 'B', creation_date: day.call(-8),
                 body: "Ship the todo.txt app +work @laptop due:#{day.call(10)}"),
        Task.new(creation_date: day.call(-6),
                 body: "Buy milk and eggs +errands @market due:#{today}"),
        Task.new(creation_date: day.call(-5),
                 body: 'Read the todo.txt spec +reading'),
        Task.new(completed: true, completion_date: day.call(-1),
                 creation_date: day.call(-10), body: 'Call mom +family @phone'),
        Task.new(priority: 'C', creation_date: day.call(-4),
                 body: "Plan the weekend trip +travel @home due:#{day.call(20)}"),
        Task.new(creation_date: day.call(-3),
                 body: "Back up laptop t:#{day.call(5)} rec:1w +maintenance @laptop")
      ]
      refresh
      flash('Demo data (not saved)')
      self
    end

    # -------------------------------------------------------------- refresh

    def refresh
      refresh_tasks
      self
    end

    def refresh_tasks
      visible = Query.filter(@tasks, @filter, @scope)
      visible = Query.sort(visible, SORT_MODES[@sort_index].first)
      @table.set_rows(visible.map { |task| row_for(task) })
      @table_box.title_right =
        "#{visible.length} shown   #{SORT_MODES[@sort_index].last}"

      open = @tasks.count { |task| !task.completed }
      done = @tasks.length - open
      overdue = @tasks.count { |task| !task.completed && task.overdue? }
      segments = [["#{open} open", :value]]
      segments << ["#{overdue} overdue", :overdue] if overdue.positive?
      segments << ["#{done} done", :success]
      @docket.segments = segments

      @root.title_right = display_path(@store.path)

      if @table.selected_row
        show_details(@table.selected_row[:task])
      else
        show_details(nil)
        @details[:status].text =
          @tasks.empty? ? 'No tasks yet — press a to add one.' : 'No task matches the filter.'
        @details[:status].style = :muted
      end
      self
    end

    def show_details(task)
      if task.nil?
        @details.each_value { |label| label.text = '' }
        @details_box.title_right = ''
        return
      end

      @source.text = task.to_s

      @details[:status].text = task.completed ? 'completed' : 'open'
      @details[:status].style = task.completed ? :done : :success

      @details[:priority].text = task.priority ? "(#{task.priority})" : '—'
      @details[:priority].style =
        task.priority ? TaskTable.priority_style(task.priority, bold: true) : :muted

      @details[:created].text = task.creation_date || '—'
      @details[:created].style = task.creation_date ? :date : :muted
      @details[:completed].text = task.completion_date || '—'
      @details[:completed].style = task.completion_date ? :date : :muted

      @details[:due].text = due_detail(task)
      @details[:due].style = due_detail_style(task)

      @details[:projects].text = list_or_dash(task.projects.map { |p| "+#{p}" })
      @details[:projects].style = task.projects.empty? ? :muted : :project
      @details[:contexts].text = list_or_dash(task.contexts.map { |c| "@#{c}" })
      @details[:contexts].style = task.contexts.empty? ? :muted : :context

      meta = task.metadata.reject { |key, _value| key == 'due' }
      @details[:meta].text = list_or_dash(meta.map { |key, value| "#{key}:#{value}" })
      @details[:meta].style = meta.empty? ? :muted : :meta

      @details_box.title_right = task.completed ? 'done' : 'open'
    end

    def row_for(task)
      {
        task: task,
        done: task.completed ? '✓' : '',
        pri: task.priority ? "(#{task.priority})" : '',
        due: due_cell(task),
        text: task.title,
        meta: (task.projects.map { |p| "+#{p}" } + task.contexts.map { |c| "@#{c}" }).join(' ')
      }
    end

    # -------------------------------------------------------------- helpers

    def apply_due(body, due)
      text = body.to_s.strip
      due = due.to_s.strip

      if due.empty?
        text.gsub(/(?:\A|\s)due:\S+/, '').gsub(/\s+/, ' ').strip
      elsif /(?:\A|\s)due:\S+/.match?(text)
        text.sub(/(?:\A|\s)due:\S+/, " due:#{due}").strip
      else
        "#{text} due:#{due}".strip
      end
    end

    def validate_priority(value)
      letter = value.to_s.strip
      return true if letter.empty? || /\A[A-Za-z]\z/.match?(letter)

      'one letter A-Z'
    end

    def validate_due(value)
      text = value.to_s.strip
      return true if text.empty?

      match = /\A(\d{4})-(\d{2})-(\d{2})\z/.match(text)
      return 'use YYYY-MM-DD' unless match
      return true if Calendar.valid?(match[1].to_i, match[2].to_i, match[3].to_i)

      'no such date'
    end

    def refresh_preview
      return unless @preview

      if @f_body.editor.value.to_s.strip.empty?
        @preview.text = '  (type a task to see the todo.txt line)'
        return
      end

      priority = @f_priority.editor.value.to_s.strip.upcase
      task = Task.new(priority: priority.empty? ? nil : priority,
                      completed: @editing ? @editing.completed : false,
                      completion_date: @editing && @editing.completion_date,
                      creation_date: @editing ? @editing.creation_date : Calendar.today,
                      body: apply_due(@f_body.editor.value, @f_due.editor.value))
      @preview.text = "  #{task}"
    end

    def due_cell(task)
      due = task.due_date
      return '' unless due
      return due if task.completed
      return "#{due} !" if task.overdue?
      return "#{due} •" if task.today?

      due
    end

    def due_detail(task)
      due = task.due_date
      return '—' unless due
      return due if task.completed

      days = Calendar.days_between(due, Calendar.today)
      label = if days.negative? then "#{-days}d overdue"
              elsif days.zero? then 'today'
              else "in #{days}d"
              end
      "#{due} (#{label})"
    rescue ArgumentError
      due
    end

    def due_detail_style(task)
      return :muted unless task.due_date
      return :done if task.completed
      return :overdue if task.overdue?
      return :due_today if task.today?

      :date
    end

    def display_path(path)
      home = Dir.home
      path.to_s.start_with?(home) ? "~#{path[home.length..-1]}" : path.to_s
    end

    def list_or_dash(list)
      list.empty? ? '—' : list.join(' ')
    end

    def show_overlay(index)
      @dialogs.set_active(index)
      @overlay.show
    end

    def hide_overlay
      @overlay.hide
      # Returning the focus to the list keeps j/k/q working right after a
      # dialog closes.
      @ui.focus(@table) if @ui
    end

    def persist
      @store.save(@tasks)
    rescue StandardError => e
      flash("Could not save: #{e.message}")
    end

    def reload_tasks
      @tasks = @store.load
      true
    rescue StandardError => e
      @tasks = []
      flash("Could not read #{@store.path}: #{e.message}")
      false
    end

    def clear_undo
      @undo = nil
    end

    # Show a message in the status row. It replaces the key hint for a few
    # seconds, then #expire_flash puts the hint back (the interactive loop
    # ticks it; a snapshot simply keeps the message).
    def flash(message)
      @status_label.text = message
      @status_label.style = :value
      @flash_until = Time.now.to_f + FLASH_SECONDS
      self
    end

    def expire_flash
      return self unless @flash_until
      return self if Time.now.to_f < @flash_until

      @flash_until = nil
      @status_label.text = HINTS[:status]
      @status_label.style = :muted
      self
    end
  end
end
