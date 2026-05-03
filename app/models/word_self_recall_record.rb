class WordSelfRecallRecord < ApplicationRecord
  belongs_to :word

  validates :is_correct, inclusion: { in: [ true, false ] }

  after_create :update_word_recall_state

  def correct?
    is_correct?
  end

  private

  def update_word_recall_state
    WordsDueForRecall.update_state_for(self)
  end
end
