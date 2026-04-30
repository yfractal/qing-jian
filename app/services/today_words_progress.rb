class TodayWordsProgress
  class << self
    def call(day: Date.current)
      reviewed_word_ids = reviewed_word_ids_for(day)
      words = today_words_for(day, reviewed_word_ids)

      words.map do |word|
        {
          word: word,
          reviewed: reviewed_word_ids.include?(word.id)
        }
      end.sort_by do |item|
        [
          item[:reviewed] ? 1 : 0,
          item[:word].word.to_s.downcase
        ]
      end
    end

    private

    def reviewed_word_ids_for(day)
      WordQuestionRecord
        .joins(:word_question)
        .where(is_correct: true, created_at: day.in_time_zone.all_day)
        .distinct
        .pluck("word_questions.word_id")
    end

    def today_words_for(day, reviewed_word_ids)
      due_words = WordsDueForRecall.call(day: day).to_a
      remembered_words = Word.where(id: reviewed_word_ids).to_a
      (due_words + remembered_words).uniq(&:id).sort_by { |word| word.word.to_s.downcase }
    end
  end
end
