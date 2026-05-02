module BookPlugin
  class BookHtml < ApplicationRecord
    belongs_to :book
    has_many :flash_cards, dependent: :nullify
    has_many_attached :images

    validates :page_number, presence: true, uniqueness: { scope: :book_id }
    validates :html, presence: true
  end
end
