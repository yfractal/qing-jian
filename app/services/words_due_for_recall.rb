class WordsDueForRecall
  SCHEDULE_INTERVALS = [ 0, 2, 3, 5, 7, 15 ].freeze

  class << self
    def call(day: Date.current)
      day = day.to_date
      due_sql, due_binds = due_conditions(day: day)

      Word
        .joins("LEFT JOIN (#{correct_stats_subquery(day: day).to_sql}) recall_stats ON recall_stats.word_id = words.id")
        .where("words.created_at <= ?", day.end_of_day)
        .where(due_sql, *due_binds)
    end

    def due?(word:, last_correct_record:, remember_times:, day:)
      return false if remember_times >= SCHEDULE_INTERVALS.size

      base_date =
        if last_correct_record
          last_correct_record.created_at.to_date
        else
          word.created_at.to_date
        end

      due_date = base_date + SCHEDULE_INTERVALS[remember_times].days
      day >= due_date
    end

    private

    def correct_stats_subquery(day:)
      WordQuestionRecord
        .joins(:word_question)
        .where(is_correct: true)
        .where("word_question_records.picked_word_id = word_questions.word_id")
        .where("word_question_records.created_at <= ?", day.end_of_day)
        .group("word_questions.word_id")
        .select(
          "word_questions.word_id AS word_id",
          "COUNT(word_question_records.id) AS remember_times",
          "MAX(word_question_records.created_at) AS last_correct_at"
        )
    end

    def due_conditions(day:)
      clauses = [ "COALESCE(recall_stats.remember_times, 0) = 0" ]
      binds = []

      SCHEDULE_INTERVALS.each_with_index do |interval_days, remember_times|
        next if remember_times.zero?

        clauses << "(recall_stats.remember_times = ? AND recall_stats.last_correct_at <= ?)"
        binds << remember_times
        binds << (day - interval_days.days).end_of_day
      end

      [ clauses.join(" OR "), binds ]
    end
  end
end
