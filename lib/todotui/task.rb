# frozen_string_literal: true

require_relative 'calendar'

module Todotui
  # A single line of a todo.txt file, parsed into its fields.
  #
  # The format (https://github.com/todotxt/todo.txt):
  #
  #   (A) 2024-01-01 Call mom +family @phone due:2024-02-01
  #   x 2024-02-02 2024-01-01 Call mom +family @phone
  #
  # * an optional priority "(A)".."(Z)" at the very start of an open task
  # * a completed task starts with "x ", then the completion date and
  #   optionally the creation date
  # * "+project" and "@context" words live in the description
  # * "key:value" metadata (due:, t:, rec:, ...) lives in the description
  #
  # Only the prefix (priority / completion / dates) is structured; the body
  # keeps the rest verbatim, so a task that is never edited round-trips
  # exactly.
  class Task
    PRIORITIES = ('A'..'Z').to_a.freeze
    DATE_RE = /\A(\d{4}-\d{2}-\d{2})(?:\s+|$)/
    PRIORITY_RE = /\A\(([A-Z])\)(?:\s+|$)/
    META_RE = /\A([A-Za-z_][A-Za-z0-9_-]*):(\S+)\z/

    attr_accessor :priority, :completed, :completion_date, :creation_date, :body

    def initialize(priority: nil, completed: false, completion_date: nil,
                   creation_date: nil, body: '')
      @priority = normalize_priority(priority)
      @completed = completed ? true : false
      @completion_date = normalize_date(completion_date)
      @creation_date = normalize_date(creation_date)
      @body = body.to_s.strip
    end

    # Parse one line. Blank lines return nil so a file full of stray
    # newlines does not turn into empty tasks.
    def self.parse(line)
      text = line.to_s.strip
      return nil if text.empty?

      match = /\Ax\s+(.*)\z/m.match(text)
      match ? parse_completed(match[1]) : parse_open(text)
    end

    # Note: the prefix helpers return [rest, value] and we assign the value
    # to the task in a separate statement. Spinel drops the setter half of a
    # chained `rest, task.attr = helper(...)`, which silently loses priority
    # and dates when reading a file in a compiled binary.
    def self.parse_completed(rest)
      task = new(completed: true)
      text, completion = take_date(rest)
      task.completion_date = completion
      if task.completion_date
        text, creation = take_date(text)
        task.creation_date = creation
      end
      text, priority = take_priority(text)
      task.priority = priority
      task.body = text.strip
      task
    end

    def self.parse_open(text)
      task = new
      rest, priority = take_priority(text)
      task.priority = priority
      rest, creation = take_date(rest)
      task.creation_date = creation
      task.body = rest.strip
      task
    end

    # Cut an optional leading date off a string: [rest, date_or_nil].
    def self.take_date(text)
      match = DATE_RE.match(text)
      return [text, nil] unless match

      [text[match[0].length..-1].to_s, match[1]]
    end

    # Cut an optional leading "(A)" off a string: [rest, letter_or_nil].
    def self.take_priority(text)
      match = PRIORITY_RE.match(text)
      return [text, nil] unless match

      [text[match[0].length..-1].to_s, match[1]]
    end

    # --- fields derived from the body ------------------------------------

    def words
      @body.split(/\s+/)
    end

    def projects
      words.select { |word| word.length > 1 && word.start_with?('+') }
           .map { |word| word[1..-1] }
    end

    def contexts
      words.select { |word| word.length > 1 && word.start_with?('@') }
           .map { |word| word[1..-1] }
    end

    # Every word that looks like key:value.
    def metadata
      words.each_with_object({}) do |word, hash|
        match = META_RE.match(word)
        hash[match[1]] = match[2] if match
      end
    end

    def due_date
      metadata['due']
    end

    def today?
      due_date == Calendar.today
    end

    def overdue?
      return false if @completed || due_date.nil?

      due_date < Calendar.today
    end

    def summary
      @body.empty? ? to_s : @body
    end

    # The bare task name: the body with +projects, @contexts and key:value
    # metadata removed, so a compact list can show just the words. If a task
    # is nothing but tags the original body is kept, so no row goes blank.
    def title
      name = words.reject { |word| tag?(word) }.join(' ')
      name.empty? ? @body : name
    end

    # --- serialisation ----------------------------------------------------

    def to_s
      parts = []
      if @completed
        parts << 'x'
        parts << @completion_date if @completion_date
        parts << @creation_date if @creation_date
        parts << "(#{@priority})" if @priority
      else
        parts << "(#{@priority})" if @priority
        parts << @creation_date if @creation_date
      end
      parts << @body
      parts.compact.reject(&:empty?).join(' ').strip
    end

    def ==(other)
      other.is_a?(Task) && to_s == other.to_s
    end

    def inspect
      "#<Todotui::Task #{to_s.inspect}>"
    end

    private

    # True for a word the list hides: a +project, an @context or key:value.
    def tag?(word)
      return true if word.length > 1 && (word.start_with?('+') || word.start_with?('@'))

      !META_RE.match(word).nil?
    end

    def normalize_priority(value)
      letter = value.to_s.strip.upcase.gsub(/[()]/, '')
      letter.length == 1 && PRIORITIES.include?(letter) ? letter : nil
    end

    def normalize_date(value)
      text = value.to_s.strip
      /\A\d{4}-\d{2}-\d{2}\z/.match?(text) ? text : nil
    end
  end
end
