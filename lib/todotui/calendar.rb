# frozen_string_literal: true

module Todotui
  # The handful of calendar operations the app needs, built on Time.
  #
  # This exists so the code runs both under CRuby and under Spinel, whose
  # packaged stdlib has no `date`. Everything the app asks for maps onto
  # Time#strftime and simple integer day math.
  module Calendar
    DAY = 86_400

    class << self
      # Today as YYYY-MM-DD.
      def today
        Time.now.strftime('%Y-%m-%d')
      end

      # Today shifted by `days` (negative for the past), as YYYY-MM-DD.
      def offset(days)
        (Time.now + (days * DAY)).strftime('%Y-%m-%d')
      end

      def valid?(year, month, day)
        time = Time.utc(year, month, day)
        time.year == year && time.month == month && time.day == day
      rescue ArgumentError
        false
      end

      # Whole days between two YYYY-MM-DD strings (a - b).
      def days_between(a, b)
        to_days(a) - to_days(b)
      end

      # Days since the Unix epoch for a YYYY-MM-DD string.
      def to_days(str)
        year, month, day = str.to_s.split('-').map(&:to_i)
        Time.utc(year, month, day).to_i / DAY
      end
    end
  end
end
