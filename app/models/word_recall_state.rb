class WordRecallState < ApplicationRecord
  belongs_to :word

  validates :remember_times, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
end
