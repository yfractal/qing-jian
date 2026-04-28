class Word < ApplicationRecord
  has_many :similar_words, as: :similar_wordable, dependent: :destroy

  validates :chinese_meaning, presence: true
  validates :english_meaning, presence: true
end
