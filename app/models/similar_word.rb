class SimilarWord < ApplicationRecord
  belongs_to :similar_wordable, polymorphic: true
  belongs_to :word

  validates :similar_wordable, presence: true
  validates :word, presence: true
end
