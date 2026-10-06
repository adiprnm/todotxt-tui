# frozen_string_literal: true

require_relative 'task'

module Todotui
  # Filtering and sorting, kept out of the widget tree so they can be
  # exercised without a terminal.
  module Query
    SORTS = %i[smart due priority alpha created completed].freeze

    module_function

    def filter(tasks, text = '', scope = 'All')
      list = case scope
             when 'Open' then tasks.reject(&:completed)
             when 'Done' then tasks.select(&:completed)
             else tasks
             end

      needle = text.to_s.strip.downcase
      return list if needle.empty?

      list.select { |task| task.to_s.downcase.include?(needle) }
    end

    def sort(tasks, mode = :smart)
      case mode
      when :due
        tasks.sort_by { |t| [t.completed ? 1 : 0, t.due_date ? 0 : 1, t.due_date || '', t.body.downcase] }
      when :priority
        tasks.sort_by { |t| [t.completed ? 1 : 0, t.priority ? 0 : 1, t.priority || '', t.body.downcase] }
      when :alpha
        tasks.sort_by { |t| t.body.downcase }
      when :created
        tasks.sort_by { |t| [t.completed ? 1 : 0, t.creation_date ? 0 : 1, t.creation_date || '', t.body.downcase] }
      when :completed
        tasks.sort_by { |t| [t.completion_date ? 0 : 1, t.completion_date || '', t.body.downcase] }
      else # :smart -- open first, then priority, then due date
        tasks.sort_by do |t|
          [t.completed ? 1 : 0, t.priority || 'ZZ',
           t.due_date || '9999-99-99', t.body.downcase]
        end
      end
    end
  end
end
