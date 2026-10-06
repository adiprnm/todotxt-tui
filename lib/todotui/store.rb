# frozen_string_literal: true

require 'fileutils'
require_relative 'task'

module Todotui
  # Reads and writes a todo.txt file. Saves go through a temp file and a
  # rename, so an interrupted write never truncates the user's list.
  class Store
    attr_reader :path, :done_path

    def initialize(path, done_path: nil)
      @path = File.expand_path(path)
      @done_path = normalize(done_path)
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

    # Append every completed task to the done.txt file. Returns how many
    # lines were archived. Without an explicit done path the archive lands
    # next to todo.txt.
    def archive(tasks)
      done = tasks.select(&:completed)
      return 0 if done.empty?

      target = @done_path || File.join(File.dirname(@path), 'done.txt')
      FileUtils.mkdir_p(File.dirname(target))
      File.open(target, 'a') { |file| done.each { |task| file.puts(task.to_s) } }
      done.length
    end

    private

    def normalize(done_path)
      value = done_path.to_s.strip
      value.empty? ? nil : File.expand_path(value)
    end
  end
end
