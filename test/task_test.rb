# frozen_string_literal: true

require_relative 'test_helper'

class TaskTest < Minitest::Test
  include TestHelpers

  def test_parses_priority_creation_date_and_body
    task = Todotui::Task.parse('(A) 2024-04-01 Call mom +family @phone due:2024-05-01')

    assert_equal true, !task.completed
    assert_equal 'A', task.priority
    assert_equal '2024-04-01', task.creation_date
    assert_equal 'Call mom +family @phone due:2024-05-01', task.body
    assert_equal ['family'], task.projects
    assert_equal ['phone'], task.contexts
    assert_equal({ 'due' => '2024-05-01' }, task.metadata)
    assert_equal '2024-05-01', task.due_date
  end

  def test_parses_completed_tasks_with_and_without_a_creation_date
    with_both = Todotui::Task.parse('x 2024-02-02 2024-01-01 Call mom')
    assert_equal true, with_both.completed
    assert_equal '2024-02-02', with_both.completion_date
    assert_equal '2024-01-01', with_both.creation_date
    assert_equal 'Call mom', with_both.body

    only_done = Todotui::Task.parse('x 2024-02-02 Call mom')
    assert_equal '2024-02-02', only_done.completion_date
    assert_nil only_done.creation_date
  end

  def test_keeps_a_priority_on_a_completed_line
    task = Todotui::Task.parse('x 2024-02-02 2024-01-01 (A) Pay rent +home')

    assert_equal true, task.completed
    assert_equal 'A', task.priority
    assert_equal 'Pay rent +home', task.body
  end

  def test_round_trips_every_kind_of_line_untouched
    lines = [
      'Buy milk',
      '(A) Call mom +family @phone',
      '(C) 2024-04-01 Ship release +work @laptop due:2024-04-02',
      'x 2024-02-02 Done thing',
      'x 2024-02-02 2024-01-01 Call mom +family @phone',
      'x 2024-02-02 2024-01-01 (A) Pay rent +home'
    ]

    lines.each do |line|
      assert_equal line, Todotui::Task.parse(line).to_s
    end
  end

  def test_blank_lines_are_skipped
    assert_nil Todotui::Task.parse('')
    assert_nil Todotui::Task.parse("   \n")
  end

  def test_priority_is_normalised_and_validated
    assert_equal 'A', Todotui::Task.new(priority: '(a)').priority
    assert_equal 'B', Todotui::Task.new(priority: 'b').priority
    assert_nil Todotui::Task.new(priority: 'AB').priority
    assert_nil Todotui::Task.new(priority: '1').priority
  end

  def test_overdue_and_today
    today = Date.today
    overdue = Todotui::Task.new(body: "old due:#{today - 1}")
    due_today = Todotui::Task.new(body: "now due:#{today}")

    assert overdue.overdue?
    assert due_today.today?
    refute due_today.overdue?
    refute Todotui::Task.new(completed: true, body: "done due:#{today - 5}").overdue?
  end

  def test_email_addresses_are_not_contexts
    task = Todotui::Task.new(body: 'mail me at foo@example.com +work')

    assert_equal ['work'], task.projects
    assert_equal [], task.contexts
  end
end
