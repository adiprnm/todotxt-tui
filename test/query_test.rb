# frozen_string_literal: true

require_relative 'test_helper'

class QueryTest < Minitest::Test
  include TestHelpers

  def tasks
    @tasks ||= [
      Todotui::Task.new(body: 'Zeta call mom +family @phone'),
      Todotui::Task.new(priority: 'B', body: 'Alpha ship app +work due:2024-05-01'),
      Todotui::Task.new(priority: 'A', body: 'Beta pay bill +home due:2024-04-01'),
      Todotui::Task.new(completed: true, completion_date: '2024-04-02', body: 'Done thing +work')
    ]
  end

  def test_filter_by_text_matches_projects_contexts_and_priorities
    assert_equal 1, Todotui::Query.filter(tasks, '+family').length
    assert_equal 1, Todotui::Query.filter(tasks, '@phone').length
    assert_equal 2, Todotui::Query.filter(tasks, '+work').length
    assert_equal tasks.length, Todotui::Query.filter(tasks, '').length
  end

  def test_filter_by_scope
    assert_equal 3, Todotui::Query.filter(tasks, '', 'Open').length
    assert_equal 1, Todotui::Query.filter(tasks, '', 'Done').length
    assert_equal 4, Todotui::Query.filter(tasks, '', 'All').length
  end

  def test_smart_sort_puts_open_then_priority
    sorted = Todotui::Query.sort(tasks, :smart)
    assert_equal ['(A) Beta pay bill +home due:2024-04-01',
                  '(B) Alpha ship app +work due:2024-05-01',
                  'Zeta call mom +family @phone',
                  'x 2024-04-02 Done thing +work'], sorted.map(&:to_s)
  end

  def test_due_sort_puts_dated_first
    sorted = Todotui::Query.sort(tasks, :due).map(&:to_s)
    assert_equal ['(A) Beta pay bill +home due:2024-04-01',
                  '(B) Alpha ship app +work due:2024-05-01',
                  'Zeta call mom +family @phone',
                  'x 2024-04-02 Done thing +work'], sorted
  end

  def test_alpha_sort
    sorted = Todotui::Query.sort(tasks, :alpha)
    assert_equal '(B) Alpha ship app +work due:2024-05-01', sorted.first.to_s
  end
end
