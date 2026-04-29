class WordsDueForRecall
  RECALL_RULES = [
    { remember_times: 0, interval_days: 0 },
    { remember_times: 1, interval_days: 2 },
    { remember_times: 2, interval_days: 3 },
    { remember_times: 3, interval_days: 5 },
    { remember_times: 4, interval_days: 7 },
    { remember_times: 5, interval_days: 15 }
  ].freeze

  class << self
    def call(day: Date.current)
      Word.joins(:word_recall_state).where(word_recall_states: { due_day: ..day.to_date })
    end

    def due?(word:, last_correct_record:, remember_times:, day:)
      due_day = next_due_day(
        word: word,
        last_correct_record: last_correct_record,
        remember_times: remember_times
      )

      due_day.present? && day.to_date >= due_day
    end

    def update_state_for(record)
      return unless record.correct?

      word = record.word_question.word
      state = WordRecallState.find_or_initialize_by(word: word)
      state.remember_times ||= 0
      state.due_day ||= word.created_at.to_date

      state.remember_times += 1
      state.due_day = next_due_day(
        word: word,
        last_correct_record: record,
        remember_times: state.remember_times
      )
      state.save!
    end

    private

    def next_due_day(word:, last_correct_record:, remember_times:)
      rule = RECALL_RULES.find { |recall_rule| recall_rule[:remember_times] == remember_times }
      return unless rule

      base_date = last_correct_record&.created_at&.to_date || word.created_at.to_date
      base_date + rule[:interval_days].days
    end
  end
end
