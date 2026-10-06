# frozen_string_literal: true

require_relative 'test_helper'

class CalendarTest < Minitest::Test
  include TestHelpers

  def test_today_matches_the_date_the_tests_use
    assert_equal Date.today.to_s, Todotui::Calendar.today
  end

  def test_offset_walks_days
    assert_equal (Date.today + 2).to_s, Todotui::Calendar.offset(2)
    assert_equal (Date.today - 9).to_s, Todotui::Calendar.offset(-9)
  end

  def test_valid_accepts_real_dates_and_rejects_the_rest
    assert Todotui::Calendar.valid?(2024, 2, 29), '2024 is a leap year'
    refute Todotui::Calendar.valid?(2023, 2, 29), '2023 is not'
    refute Todotui::Calendar.valid?(2024, 13, 1)
    refute Todotui::Calendar.valid?(2024, 4, 31)
  end

  def test_days_between_counts_whole_days
    assert_equal 2, Todotui::Calendar.days_between('2024-03-01', '2024-02-28')
    assert_equal(-1, Todotui::Calendar.days_between('2024-02-28', '2024-02-29'))
    assert_equal 0, Todotui::Calendar.days_between('2024-02-28', '2024-02-28')
  end

  def test_days_between_is_exact_across_year_ends
    assert_equal 365, Todotui::Calendar.days_between('2023-12-31', '2022-12-31')
    assert_equal 366, Todotui::Calendar.days_between('2024-12-31', '2023-12-31')
    assert_equal 1, Todotui::Calendar.days_between('2024-01-01', '2023-12-31')
  end
end
