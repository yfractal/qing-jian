module BookPlugin
  class FlashCard < ApplicationRecord
    belongs_to :book
    belongs_to :book_html

    validates :book_html_id, presence: true
  end
end
