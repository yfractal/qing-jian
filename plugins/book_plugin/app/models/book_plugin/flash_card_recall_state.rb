module BookPlugin
  class FlashCardRecallState < ApplicationRecord
    belongs_to :flash_card
  end
end
