# frozen_string_literal: true

require 'ruby-tui'

module Todotui
  # A one-line label built from styled segments. The stock Label carries a
  # single style; the summary rail needs a few, so "6 open" can sit grey
  # next to "1 overdue" in red without two labels fighting over one row.
  class RichLabel < TUI::Component
    attr_accessor :segments, :gap, :align

    # segments: [[text, style], ...]
    def initialize(segments = [], align: :left, gap: 2, **opts)
      super(**opts)
      @segments = segments
      @align = align
      @gap = gap
    end

    def text
      @segments.map { |segment| segment[0] }.join(' ' * @gap)
    end

    def measure(max_w, max_h)
      [[natural_width, max_w].min, [1, max_h].min]
    end

    def render(canvas)
      x = @rect.x
      x += [@rect.w - natural_width, 0].max if @align == :right
      @segments.each_with_index do |(value, style), i|
        x += @gap if i.positive?
        canvas.put(x, @rect.y, value, style)
        x += TUI::Text.width(value)
      end
      self
    end

    private

    def natural_width
      @segments.sum { |segment| TUI::Text.width(segment[0]) } +
        (@gap * [@segments.length - 1, 0].max)
    end
  end
end
