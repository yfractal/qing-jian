class WordQuestionRecord < ApplicationRecord
  belongs_to :word_question
  belongs_to :picked_word, class_name: "Word", foreign_key: :picked_word_id

  validates :word_question, presence: true
  validates :picked_word, presence: true

  after_create :update_word_recall_state

  def correct?
    is_correct
  end

  private

  def update_word_recall_state
    WordsDueForRecall.update_state_for(self)
  end
end
