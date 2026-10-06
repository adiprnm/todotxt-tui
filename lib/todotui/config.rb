# frozen_string_literal: true

require 'fileutils'

module Todotui
  # The app config: a tiny key=value file kept at
  # $XDG_CONFIG_HOME/todotui/config (or ~/.config/todotui/config). It
  # remembers where the user's todo.txt and done.txt live.
  class Config
    # Only the namespaced variable is honored. Generic names such as
    # TODO_FILE / TODO_TXT are exported by other todo.txt tools (todo.sh and
    # friends) and would silently hijack the file this app opens, beating a
    # path the user set in the config or in Settings.
    ENV_KEYS = %w[TODOTXT_FILE].freeze
    DONE_ENV_KEYS = %w[TODOTXT_DONE_FILE].freeze
    FILENAME = 'todo.txt'
    DONE_FILENAME = 'done.txt'

    attr_reader :path
    attr_accessor :todo_file, :done_file

    def self.dir
      base = ENV['XDG_CONFIG_HOME'].to_s
      base = File.join(Dir.home, '.config') if base.empty?
      File.join(base, 'todotui')
    end

    def self.default_path
      File.join(dir, 'config')
    end

    def self.default_todo_file
      File.join(Dir.home, FILENAME)
    end

    def self.default_done_file
      File.join(Dir.home, DONE_FILENAME)
    end

    def initialize(path: self.class.default_path)
      @path = File.expand_path(path)
      @todo_file = self.class.default_todo_file
      @done_file = nil
      load
    end

    # The file in effect, in order of precedence:
    #   explicit argument > environment > config file > default
    def resolve(explicit = nil)
      return File.expand_path(explicit) if present?(explicit)

      ENV_KEYS.each do |key|
        return File.expand_path(ENV[key]) if present?(ENV[key])
      end
      File.expand_path(@todo_file)
    end

    # Where completed tasks are archived, with the same precedence as
    # #resolve. When nothing is configured it falls back to done.txt next to
    # the todo.txt in effect, which is the classic todo.txt layout.
    def resolve_done(explicit = nil, todo: nil)
      return File.expand_path(explicit) if present?(explicit)

      DONE_ENV_KEYS.each do |key|
        return File.expand_path(ENV[key]) if present?(ENV[key])
      end
      return File.expand_path(@done_file) if present?(@done_file)

      File.join(File.dirname(todo || resolve), DONE_FILENAME)
    end

    def load
      return self unless File.file?(@path)

      File.foreach(@path) do |line|
        line = line.strip
        next if line.empty? || line.start_with?('#')

        key, value = line.split('=', 2)
        next if value.nil?

        @todo_file = value.strip if key.strip == 'todo_file'
        @done_file = value.strip if key.strip == 'done_file'
      end
      self
    end

    def save
      FileUtils.mkdir_p(File.dirname(@path))
      lines = [
        '# todotui configuration',
        '# where your todo.txt and done.txt live',
        "todo_file=#{@todo_file}"
      ]
      lines << "done_file=#{@done_file}" if present?(@done_file)
      File.write(@path, "#{lines.join("\n")}\n")
      self
    end

    private

    def present?(value)
      !value.nil? && !value.to_s.strip.empty?
    end
  end
end
