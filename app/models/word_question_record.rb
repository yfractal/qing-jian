class WordQuestionRecord < ApplicationRecord
  belongs_to :word_question

  validates :word_question, presence: true
  validates :picked_choice_token, presence: true
  validates :picked_choice_word, presence: true

  after_create :update_word_recall_state

  def correct?
    is_correct
  end

  private

  def update_word_recall_state
    WordsDueForRecall.update_state_for(self)
  end
end
