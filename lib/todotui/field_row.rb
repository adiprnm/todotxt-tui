# frozen_string_literal: true

require 'ruby-tui'

module Todotui
  # A label / value pair that wraps in the space it is actually given.
  #
  # A nested Layout::Stack cannot do this: when it measures a wrapping label
  # it hands over the whole row width, not what is left after the label, so
  # a long value is allotted one line and then clipped. This row measures
  # the value against `width - label_width` instead.
  class FieldRow < TUI::Component
    attr_accessor :label_width

    def initialize(label, label_width: 11, label_style: :label, value_style: :value)
      super()
      @label_width = label_width
      @label = TUI::Label.new(label, style: label_style)
      @value = TUI::Label.new('', style: value_style, wrap: true)
      add(@label)
      add(@value)
    end

    # Delegate the text bit to the value side, so a FieldRow can stand in
    # for the Label it replaces (and reads the same in tests).
    def text
      @value.text
    end

    def text=(value)
      @value.text = value
      self
    end

    def style=(style)
      @value.style = style
      self
    end

    def measure(max_w, max_h)
      width = value_width(max_w)
      lines = TUI::Text.wrap(@value.text, width)
      [max_w, [[lines.length, 1].max, max_h].min]
    end

    def layout(rect)
      @rect = rect
      @label.layout(TUI::Rect.new(rect.x, rect.y, @label_width, 1))
      @value.layout(TUI::Rect.new(rect.x + @label_width, rect.y,
                                  value_width(rect.w), rect.h))
      self
    end

    private

    def value_width(total)
      [total - @label_width, 1].max
    end
  end
end
