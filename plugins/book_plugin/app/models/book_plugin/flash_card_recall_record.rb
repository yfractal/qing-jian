module BookPlugin
  class FlashCardRecallRecord < ApplicationRecord
    belongs_to :flash_card

    validates :is_correct, inclusion: { in: [true, false] }

    after_create :update_flash_card_recall_state

    def correct?
      is_correct?
    end

    private

    def update_flash_card_recall_state
      FlashCardsDueForRecall.update_state_for(self)
    end
  end
end
