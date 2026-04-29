class Word < ApplicationRecord
  has_many :similar_words, as: :similar_wordable, dependent: :destroy
  has_many :word_questions, dependent: :destroy
  has_many :word_question_records, foreign_key: :picked_word_id, dependent: :destroy

  validates :word, presence: true, uniqueness: { case_sensitive: false }
  validates :chinese_meaning, presence: true
  validates :english_meaning, presence: true
end
