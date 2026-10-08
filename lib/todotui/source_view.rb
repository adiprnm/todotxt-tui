# frozen_string_literal: true

require 'ruby-tui'

require_relative 'table'

module Todotui
  # The details hero: a todo.txt line painted token by token.
  #
  # Every other panel is chrome; this one shows the artefact the app is
  # built around, with its grammar made visible -- the priority in its
  # colour, +project and @context in theirs, dates and key:value metadata
  # in their own. A raw string is accepted too (for the empty state), in
  # which case it is painted as plain text.
  #
  #   view = SourceView.new
  #   view.text = task.to_s
  class SourceView < TUI::Component
    attr_reader :style

    def initialize(text = '', style: :text, **opts)
      super(**opts)
      @text = text.to_s
      @style = style
    end

    def text
      @text
    end

    def text=(value)
      @text = value.to_s
      self
    end

    def measure(max_w, max_h)
      lines = wrapped(max_w)
      widths = lines.map { |line| line_width(line) }
      [[widths.max.to_i, max_w].min, [lines.length, max_h].min]
    end

    def render(canvas)
      wrapped(@rect.w).first(@rect.h).each_with_index do |line, row|
        x = @rect.x
        line.each do |(value, style)|
          canvas.put(x, @rect.y + row, value, style)
          x += TUI::Text.width(value)
        end
      end
      self
    end

    private

    # Word wrap that keeps every token's style, so a styled token is never
    # split mid-word. Returns an array of lines, each a list of
    # [text, style] segments (spaces included).
    def wrapped(width)
      words = @text.split(/\s+/).reject(&:empty?)
      lines = []
      current = []
      used = 0

      words.each_with_index do |word, index|
        style = style_for(word, index)
        size = TUI::Text.width(word)
        gap = current.empty? ? 0 : 1
        if !current.empty? && used + gap + size > width
          lines << current
          current = []
          used = 0
          gap = 0
        end

        current << [' ', @style] if gap == 1
        current << [word, style]
        used += gap + size
      end

      lines << current unless current.empty?
      lines << [] if lines.empty?
      lines
    end

    # The token rules mirror todotui's Task parser, but only for colouring:
    # nothing is validated or re-serialised here.
    def style_for(word, index)
      return :done if index.zero? && word == 'x'
      return TaskTable.priority_style(word[1], bold: true) if /\A\(([A-Z])\)\z/.match?(word)
      return :date if /\A\d{4}-\d{2}-\d{2}\z/.match?(word)
      return :project if word.length > 1 && word.start_with?('+')
      return :context if word.length > 1 && word.start_with?('@')
      return :meta if /\A[A-Za-z_][A-Za-z0-9_-]*:\S+\z/.match?(word)

      @style
    end

    def line_width(line)
      line.sum { |segment| TUI::Text.width(segment[0]) }
    end
  end
end
