# frozen_string_literal: true

require 'ruby-tui'

module Todotui
  # Todotui's take on the stock theme: cool graphite chrome with a single
  # warm accent, plus semantic styles for the todo.txt vocabulary.
  #
  # The stock theme deliberately keeps its accent hueless so it never fights
  # the terminal, which makes chrome and data look equally grey. Here the
  # chrome stays grey and the accent (amber) and the data (+project,
  # @context, due:, dates) carry the colour, so the eye lands on tasks.
  #
  #   Todotui::Theme.install(:dark)     # colour + attributes
  #   Todotui::Theme.install(:plain)    # attributes only
  module Theme
    # Layered on top of TUI::Theme::DARK.
    DARK = {
      # The one warm colour in the chrome: focus rings, the sort marker,
      # "due today".
      accent:      { fg: 214, bold: true },
      accent2:     { fg: 209 },

      brand:       { fg: 231, bold: true },
      brand_path:  { fg: 243 },
      rule:        { fg: 238 },

      # The todo.txt vocabulary. Each token kind gets one stable colour so
      # the same word reads the same everywhere it appears.
      date:        { fg: 109 },
      project:     { fg: 79 },
      context:     { fg: 140 },
      meta:        { fg: 179 },
      overdue:     { fg: 203, bold: true },
      due_soon:    { fg: 214, bold: true },
      due_today:   { fg: 214, bold: true },
      done:        { fg: 243, dim: true },

      check:       { fg: 78 },
      meter_fill:  { fg: 78 },
      meter_track: { fg: 238 }
    }.freeze

    # Layered on top of TUI::Theme::PLAIN. Status colours stay (there the
    # colour is information, not decoration); the vocabulary keeps its
    # meaning through weight instead of hue.
    PLAIN = {
      accent:      { bold: true },
      accent2:     { bold: true },
      brand:       { bold: true },
      brand_path:  { dim: true },
      rule:        { dim: true },

      date:        {},
      project:     { bold: true },
      context:     { underline: true },
      meta:        { italic: true },
      overdue:     { bold: true, reverse: true },
      due_soon:    { bold: true },
      due_today:   { bold: true, underline: true },
      done:        { dim: true },

      check:       { bold: true },
      meter_fill:  { bold: true },
      meter_track: { dim: true }
    }.freeze

    class << self
      # Install the stock theme, then layer Todotui's styles on top.
      def install(name = :dark)
        name = name.respond_to?(:to_sym) ? name.to_sym : name
        base = name == :plain ? :plain : :dark
        TUI::Theme.install(base)

        styles = base == :plain ? PLAIN : DARK
        # Style.define takes the opts hash positionally: forwarding it with
        # **opts is a construct Spinel refuses to compile.
        styles.each { |style_name, opts| TUI::Style.define(style_name, opts) }
        self
      end
    end
  end
end

Todotui::Theme.install(:dark)
