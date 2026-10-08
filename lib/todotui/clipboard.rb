# frozen_string_literal: true

module Todotui
  # Hand a string to the desktop clipboard. There is no portable API, so try
  # the usual suspects in turn: Wayland's wl-copy, X11's xclip/xsel and macOS's
  # pbcopy. Every tool reads the selection from stdin, so one pipe covers all
  # of them.
  #
  # Open3/IO.popen are unavailable under Spinel, so the text is single-quoted
  # into a `printf` pipeline and handed to the shell. The text is a task name,
  # never a command, so quoting it safely is all that is needed.
  module Clipboard
    COMMANDS = [
      'wl-copy',
      'xclip -selection clipboard',
      'xsel --clipboard --input',
      'pbcopy'
    ].freeze

    class << self
      # Every clipboard tool found on $PATH, in preference order.
      def available
        path = ENV['PATH']
        COMMANDS.select { |argv| executable?(argv.split(' ').first, path) }
      end

      # The first clipboard tool found on $PATH, or nil.
      def command
        available.first
      end

      # Copy +text+ and return the command that took it, or nil when none did.
      # A tool that is installed but broken (no compositor, say) is skipped so
      # the next candidate gets a turn.
      def copy(text)
        available.each do |argv|
          return argv if system("printf %s #{shell_quote(text.to_s)} | #{argv} 2>/dev/null")
        end
        nil
      end

      private

      def executable?(name, path)
        path.to_s.split(File::PATH_SEPARATOR).any? do |dir|
          !dir.empty? && File.executable?(File.join(dir, name))
        end
      end

      # Wrap in single quotes for /bin/sh; a literal quote becomes '\''.
      def shell_quote(text)
        "'" + text.split("'").join("'\\''") + "'"
      end
    end
  end
end
