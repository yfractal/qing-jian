module BookPlugin
  class Book < ApplicationRecord
    has_one_attached :file
    has_many :book_htmls, dependent: :destroy
    has_many :flash_cards, dependent: :destroy
    has_many :flash_card_recall_records, through: :flash_cards, source: :recall_records

    validates :title, presence: true
    validate :file_must_be_attached
    validate :file_must_be_pdf

    private

    def file_must_be_attached
      errors.add(:file, "must be attached") unless file.attached?
    end

    def file_must_be_pdf
      return unless file.attached?
      return if file.blob.content_type == "application/pdf"

      errors.add(:file, "must be a PDF")
    end
  end
end
