# frozen_string_literal: true

require 'fileutils'
require_relative 'task'

module Todotui
  # Reads and writes a todo.txt file. Saves go through a temp file and a
  # rename, so an interrupted write never truncates the user's list.
  class Store
    attr_reader :path

    def initialize(path)
      @path = File.expand_path(path)
    end

    def exist?
      File.file?(@path)
    end

    def load
      return [] unless exist?

      File.readlines(@path, chomp: true).map { |line| Task.parse(line) }.compact
    end

    def save(tasks)
      FileUtils.mkdir_p(File.dirname(@path))
      body = tasks.map(&:to_s).reject(&:empty?)
      text = body.empty? ? '' : "#{body.join("\n")}\n"
      tmp = "#{@path}.tmp"
      File.write(tmp, text)
      File.rename(tmp, @path)
      self
    end

    # Append every completed task to a sibling done.txt. Returns how many
    # lines were archived.
    def archive(tasks)
      done = tasks.select(&:completed)
      return 0 if done.empty?

      done_path = File.join(File.dirname(@path), 'done.txt')
      File.open(done_path, 'a') { |file| done.each { |task| file.puts(task.to_s) } }
      done.length
    end
  end
end
