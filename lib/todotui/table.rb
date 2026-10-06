# frozen_string_literal: true

require 'ruby-tui'

module Todotui
  # A TUI::Table that paints every priority a colour of its own.
  #
  # The stock table styles a whole row with a single style, so there is no
  # per-cell hook. We override the row painter instead and tint the entire
  # line -- the task text, the due date and the badges -- with the task's
  # priority colour. The cursor row still uses the selection highlight so
  # the cursor stays visible.
  class TaskTable < TUI::Table
    # A..Z walked around the 256-colour wheel: red, oranges, yellows, greens,
    # cyans, blues, violets, magentas and back. Keep the letters aligned with
    # the colours so `(A)` always reads the same.
    COLORS = %w[
      196 202 208 214 220 226 190 154 118 82 46 51
      45 39 33 27 57 93 129 165 201 207 213 219 225 231
    ].freeze

    PRIORITY_COLORS = ('A'..'Z').zip(COLORS).to_h do |letter, code|
      [letter, TUI::Style.fg(code.to_i)]
    end.freeze

    # The SGR string for a priority letter, or :text when there is none.
    def self.priority_style(priority)
      PRIORITY_COLORS[priority.to_s.upcase] || :text
    end

    private

    def draw_row(canvas, area, row, index, line)
      rect = TUI::Rect.new(area.x, area.y + line, area.w, 1)
      selected = index == @selected
      if selected
        canvas.fill(rect.x, rect.y, rect.w, 1, ' ',
                    focused? ? @selected_style : @dim_style)
      end

      style = selected ? (focused? ? @selected_style : @dim_style) : row_style(row)
      @columns.each_with_index do |column, i|
        cell_rect = TUI::Rect.new(rect.x + column_offset(i), rect.y, @widths[i], 1)
        canvas.text(cell_rect, column.cell(row, i), style, column.align)
      end
      self
    end

    # One colour for the whole line, picked from the task's priority.
    def row_style(row)
      priority = row[:task]&.priority
      priority ? self.class.priority_style(priority) : @style
    end
  end
end
