class SimilarWord < ApplicationRecord
  belongs_to :word_question

  validates :word, presence: true
  validates :english_meaning, presence: true
  validates :chinese_meaning, presence: true
end
