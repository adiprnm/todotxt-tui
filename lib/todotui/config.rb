# frozen_string_literal: true

require 'fileutils'

module Todotui
  # The app config: a tiny key=value file kept at
  # $XDG_CONFIG_HOME/todotui/config (or ~/.config/todotui/config). It
  # remembers where the user's todo.txt lives.
  class Config
    ENV_KEYS = %w[TODOTXT_FILE TODO_FILE TODO_TXT].freeze
    FILENAME = 'todo.txt'

    attr_reader :path
    attr_accessor :todo_file

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

    def initialize(path: self.class.default_path)
      @path = File.expand_path(path)
      @todo_file = self.class.default_todo_file
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

    def load
      return self unless File.file?(@path)

      File.foreach(@path) do |line|
        line = line.strip
        next if line.empty? || line.start_with?('#')

        key, value = line.split('=', 2)
        next if value.nil?

        @todo_file = value.strip if key.strip == 'todo_file'
      end
      self
    end

    def save
      FileUtils.mkdir_p(File.dirname(@path))
      File.write(@path, "# todotui configuration\n" \
                        "# where your todo.txt lives\n" \
                        "todo_file=#{@todo_file}\n")
      self
    end

    private

    def present?(value)
      !value.nil? && !value.to_s.strip.empty?
    end
  end
end
