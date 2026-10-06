# frozen_string_literal: true

require 'stringio'
require 'ruby-tui'

require_relative 'app'
require_relative 'config'

module Todotui
  # Command line entry point: option parsing, the interactive loop and the
  # off-screen `--snapshot` mode.
  module CLI
    USAGE = <<~TEXT
      todotui -- a todo.txt manager built on ruby-tui

        todotui                         open the configured todo.txt
        todotui --file=~/work/todo.txt  open a specific file for this run
        todotui --snapshot --demo       dump one frame to stdout
        todotui --theme=plain           no colours at all

      options:
        --file=PATH        todo.txt to open (beats the env vars and the config)
        --config=PATH      config file to use (default ~/.config/todotui/config)
        --snapshot         render one frame and exit, no terminal needed
        --demo             fill the frame with example tasks (never saved)
        --theme=dark|plain pick a theme
        --w=NUM --h=NUM    snapshot size (default 100x30)
        -h, --help         show this help

      environment:
        TODOTXT_FILE / TODO_FILE / TODO_TXT   path to todo.txt

      keys:
        a add · space complete · enter edit · d delete · u undo
        j/k or arrows move · s sort · / filter · , settings · q quit
    TEXT

    class << self
      def run(argv)
        options = parse(argv)
        TUI::Theme.install(options[:theme]) if options[:theme]

        config = Config.new(path: options[:config] || Config.default_path)
        app = App.new(config: config, file: options[:file])
        app.demo! if options[:demo]
        options[:snapshot] ? snapshot(app, options) : interactive(app)
        app
      end

      def parse(argv)
        options = { snapshot: false, demo: false, w: nil, h: nil }
        argv.each do |arg|
          case arg
          when '--snapshot'           then options[:snapshot] = true
          when '--demo'               then options[:demo] = true
          when /\A--file=(.+)\z/      then options[:file] = Regexp.last_match(1)
          when /\A--config=(.+)\z/    then options[:config] = Regexp.last_match(1)
          when /\A--theme=(\w+)\z/    then options[:theme] = Regexp.last_match(1)
          when /\A--w=(\d+)\z/        then options[:w] = Regexp.last_match(1).to_i
          when /\A--h=(\d+)\z/        then options[:h] = Regexp.last_match(1).to_i
          when '-h', '--help'         then puts USAGE
                                         exit 0
          else
            warn "todotui: unknown option #{arg.inspect}"
            puts USAGE
            exit 1
          end
        end
        options
      end

      # Render into an off-screen canvas and print it: no raw mode, no
      # alternate screen, safe over a pipe and in tests.
      def snapshot(app, options)
        cols = options[:w] || 100
        rows = options[:h] || 30
        ui = TUI::App.new(app.root, out: StringIO.new, size: [cols, rows])
        app.attach(ui)
        app.resize(cols, rows)
        app.refresh
        print ui.render_lines.join("\n"), "\n"
        print TUI::Style::RESET
      end

      def interactive(app)
        ui = TUI::App.new(app.root)
        app.attach(ui)

        ui.on_key('q') { ui.quit }
        ui.on_key(:ctrl_c) { ui.quit }
        ui.on_key('a') { app.open_editor }
        ui.on_key('e') { app.open_editor(app.selected_task) }
        ui.on_key(' ') { app.toggle_selected }
        ui.on_key('d') { app.delete_selected }
        ui.on_key('u') { app.undo_delete }
        ui.on_key('j') { app.move_selection(1) }
        ui.on_key('k') { app.move_selection(-1) }
        ui.on_key('s') { app.cycle_sort }
        ui.on_key('A') { app.archive_done }
        ui.on_key(',') { app.open_settings }
        ui.on_key('/') { app.focus_filter }
        ui.on_key(:escape) { app.cancel }
        ui.on_key(:left) { app.move_selection(-1) }
        ui.on_key(:right) { app.move_selection(1) }

        ui.on_resize { |cols, rows| app.resize(cols, rows) }
        app.resize(*ui.size)
        app.focus_list
        ui.run
      end
    end
  end
end
