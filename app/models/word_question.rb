class WordQuestion < ApplicationRecord
  belongs_to :word
  has_many :similar_words, as: :similar_wordable, dependent: :destroy
  has_many :word_question_records, dependent: :destroy

  validates :word, presence: true
  validate :exactly_three_similar_words

  def choices
    [ word ] + similar_words.map(&:word)
  end

  private

  def exactly_three_similar_words
    return if similar_words.reject(&:marked_for_destruction?).size == 3

    errors.add(:similar_words, "must have exactly 3")
  end
end
