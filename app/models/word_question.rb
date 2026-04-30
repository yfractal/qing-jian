class WordQuestion < ApplicationRecord
  Choice = Data.define(:token, :word, :english_meaning, :chinese_meaning, :correct)

  belongs_to :word
  has_many :similar_words, dependent: :destroy
  has_many :word_question_records, dependent: :destroy

  validates :word, presence: true
  validate :exactly_three_similar_words

  def choices
    [
      Choice.new(
        token: "word:#{word.id}",
        word: word.word,
        english_meaning: word.english_meaning,
        chinese_meaning: word.chinese_meaning,
        correct: true
      )
    ] + similar_words.map do |similar_word|
      Choice.new(
        token: "similar_word:#{similar_word.id}",
        word: similar_word.word,
        english_meaning: similar_word.english_meaning,
        chinese_meaning: similar_word.chinese_meaning,
        correct: false
      )
    end
  end

  def choice_for_token(token)
    choices.find { |choice| choice.token == token }
  end

  private

  def exactly_three_similar_words
    return if similar_words.reject(&:marked_for_destruction?).size == 3

    errors.add(:similar_words, "must have exactly 3")
  end
end
