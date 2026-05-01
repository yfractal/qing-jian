class RememberWordsStatistics
  LEVEL_THRESHOLDS = [0.0, 0.25, 0.5, 0.75].freeze

  # GitHub-style grid: 53 columns × 7 rows so the last cell is the calendar end day.
  HEATMAP_GRID_DAYS = 53 * 7 - 1

  class << self
    def call(day: Date.current, days: HEATMAP_GRID_DAYS)
      end_day = day.to_date
      date_range = (end_day - (days - 1).days)..end_day
      daily_review_counts = daily_review_counts_for(date_range)
      filled_counts = fill_missing_days(date_range, daily_review_counts)

      total_words = Word.count
      remembered_words = WordRecallState.where("remember_times >= ?", 6).count
      reviews_today = filled_counts[end_day].to_i

      {
        total_words: total_words,
        remembered_words: remembered_words,
        completion_rate_percent: percent(remembered_words, total_words),
        daily_review_counts: filled_counts,
        reviews_today: reviews_today,
        heatmap_max_count: [daily_review_counts.values.max.to_i, 1].max,
        reviews_last_7_days: reviews_in_window(day: end_day, days: 7),
        reviews_last_30_days: reviews_in_window(day: end_day, days: 30),
        active_days_last_30_days: active_days_in_window(day: end_day, days: 30)
      }
    end

    def heat_level(count:, max_count:)
      return 0 if count.to_i <= 0
      return 4 if max_count.to_i <= 1

      ratio = count.to_f / max_count.to_f
      LEVEL_THRESHOLDS.count { |threshold| ratio > threshold }
    end

    private

    def daily_review_counts_for(date_range)
      WordQuestionRecord
        .where(created_at: date_range.first.in_time_zone.beginning_of_day..date_range.last.in_time_zone.end_of_day)
        .group("DATE(created_at)")
        .count
        .transform_keys(&:to_date)
    end

    def fill_missing_days(date_range, counts)
      date_range.each_with_object({}) do |date, hash|
        hash[date] = counts[date].to_i
      end
    end

    def reviews_in_window(day:, days:)
      start_day = day - (days - 1).days
      range = start_day.in_time_zone.beginning_of_day..day.in_time_zone.end_of_day
      WordQuestionRecord.where(created_at: range).count
    end

    def active_days_in_window(day:, days:)
      start_day = day - (days - 1).days
      range = start_day.in_time_zone.beginning_of_day..day.in_time_zone.end_of_day

      WordQuestionRecord
        .where(created_at: range)
        .group("DATE(created_at)")
        .count
        .keys
        .size
    end

    def percent(numerator, denominator)
      return 0 if denominator.zero?

      ((numerator.to_f / denominator) * 100).round
    end
  end
end
