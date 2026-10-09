# frozen_string_literal: true

require 'ruby-tui'

module Todotui
  # A TUI::Table tuned for todo.txt lines.
  #
  # The stock table paints every cell with one row style, which can only
  # express "this row belongs to priority B". A task line is richer than
  # that: the priority is a colour tab in the gutter and a tinted badge,
  # the due date carries urgency, and +projects / @contexts read as tags.
  # We override the row painter to style each cell for what it holds.
  #
  # The cursor row keeps the selection highlight, but the priority tab and
  # badge stay coloured on top of it so the cursor never hides priority.
  class TaskTable < TUI::Table
    # A..Z walked around the 256-colour wheel: red, oranges, yellows, greens,
    # cyans, blues, violets, magentas and back. Keep the letters aligned with
    # the colours so `(A)` always reads the same.
    COLORS = %w[
      196 202 208 214 220 226 190 154 118 82 46 51
      45 39 33 27 57 93 129 165 201 207 213 219 225 231
    ].freeze

    # letter => colour code, so a lookup never rebuilds the alphabet.
    PRIORITY_COLORS = ('A'..'Z').zip(COLORS).to_h.freeze

    # A priority's colour code, or nil when the task has none.
    def self.priority_color(priority)
      PRIORITY_COLORS[priority.to_s.upcase]
    end

    # The SGR string for a priority letter, or :text when there is none.
    # `bold:` is used by badges and the source view, where the letter should
    # read a little heavier than the text around it.
    def self.priority_style(priority, bold: false)
      code = priority_color(priority)
      return :text unless code

      bold ? "\e[1;38;5;#{code}m" : TUI::Style.fg(code)
    end

    # TUI::Table binds 's' to its own column sort, and a focused widget
    # consumes keys before TUI::App#dispatch reaches the global bindings.
    # That swallowed App#cycle_sort (its own cycle_sort is a no-op here,
    # since this table is not `sortable`). Let 's' fall through so the app
    # owns sorting again.
    def handle_key(key)
      return false if key.name == 's'

      super
    end

    private

    def draw_row(canvas, area, row, index, line)
      rect = TUI::Rect.new(area.x, area.y + line, area.w, 1)
      selected = index == @selected
      base = selected ? (focused? ? @selected_style : @dim_style) : @style
      canvas.fill(rect.x, rect.y, cursor_width(row, rect.w), 1, ' ', base) if selected

      task = row[:task]
      @columns.each_with_index do |column, i|
        cell = TUI::Rect.new(rect.x + column_offset(i), rect.y, @widths[i], 1)
        draw_cell(canvas, cell, column, row, task, selected, base)
      end
      self
    end

    # The cursor bar hugs the row's content instead of running the full
    # width of the panel: it stops one cell after the last column that has
    # anything to show, so a short task leaves a short bar.
    def cursor_width(row, limit)
      width = 1
      @columns.each_with_index do |column, i|
        value = column.cell(row, i).to_s
        next if value.empty?

        width = [column_offset(i) + TUI::Text.width(value), limit].min
      end
      [width + 1, limit].min
    end

    def draw_cell(canvas, cell, column, row, task, selected, base)
      case column.key
      when :flag
        draw_flag(canvas, cell, task)
      when :done
        canvas.text(cell, column.cell(row, 0), task&.completed ? :check : base, column.align)
      when :pri
        canvas.text(cell, column.cell(row, 0), priority_style(task, selected, base), column.align)
      when :due
        canvas.text(cell, column.cell(row, 0), due_style(task, selected, base), column.align)
      when :meta
        selected ? canvas.text(cell, column.cell(row, 0), base, column.align)
                 : draw_meta(canvas, cell, task)
      else
        style = if selected then base
                elsif task&.completed then :done
                else @style
                end
        canvas.text(cell, column.cell(row, 0), style, column.align)
      end
    end

    # A coloured tab in the left gutter -- the at-a-glance priority. Rows
    # without a priority get no tab, so A..Z tasks stand out.
    def draw_flag(canvas, rect, task)
      color = self.class.priority_color(task&.priority)
      return unless color

      canvas.put(rect.x, rect.y, '▌', TUI::Style.fg(color.to_i))
      self
    end

    def priority_style(task, selected, base)
      priority = task&.priority
      return selected ? base : @style unless priority

      self.class.priority_style(priority, bold: true)
    end

    def due_style(task, selected, base)
      return base if selected || task.nil?
      return :done if task.completed
      return base unless task.due_date
      return :overdue if task.overdue?
      return :due_today if task.today?

      :date
    end

    # +projects in one colour, @contexts in another, in the same cell. The
    # stock table can only give a cell one style, so this draws the
    # segments itself and stops at the column edge.
    def draw_meta(canvas, rect, task)
      return self unless task

      segments = []
      projects = task.projects.map { |name| "+#{name}" }
      contexts = task.contexts.map { |name| "@#{name}" }
      segments << [projects.join(' '), :project] unless projects.empty?
      segments << [' ', @style] unless projects.empty? || contexts.empty?
      segments << [contexts.join(' '), :context] unless contexts.empty?

      x = rect.x
      limit = rect.x + rect.w
      catch(:full) do
        segments.each do |(value, style)|
          throw :full if x >= limit

          remaining = limit - x
          text = TUI::Text.width(value) > remaining ? TUI::Text.truncate(value, remaining) : value
          canvas.put(x, rect.y, text, style)
          x += TUI::Text.width(text)
        end
      end
      self
    end
  end
end
