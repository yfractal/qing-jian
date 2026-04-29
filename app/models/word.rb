class Word < ApplicationRecord
  has_many :similar_words, as: :similar_wordable, dependent: :destroy
  has_many :word_questions, dependent: :destroy
  has_many :word_question_records, foreign_key: :picked_word_id, dependent: :destroy
  has_one :word_recall_state, dependent: :destroy

  validates :word, presence: true, uniqueness: { case_sensitive: false }
  validates :chinese_meaning, presence: true
  validates :english_meaning, presence: true

  after_create :create_initial_recall_state

  private

  def create_initial_recall_state
    create_word_recall_state!(due_day: created_at.to_date)
  end
end
