module BookPlugin
  class BookHtml < ApplicationRecord
    belongs_to :book
    has_many :flash_cards, dependent: :nullify

    validates :page_number, presence: true, uniqueness: { scope: :book_id }
    validate :layout_structure

    def rendered_html(scale: 1.5, area: nil, load_js: true)
      PdfPageHtmlRenderer.render(
        layout: layout.fetch("items"),
        width: layout.fetch("width"),
        height: layout.fetch("height"),
        scale:,
        area:,
        load_js:
      )
    end

    private

    def layout_structure
      unless layout.is_a?(Hash)
        errors.add(:layout, "must be present")
        return
      end
      unless layout["items"].is_a?(Array)
        errors.add(:layout, "must include items")
      end
      errors.add(:layout, "must include width") unless layout.key?("width")
      errors.add(:layout, "must include height") unless layout.key?("height")
    end
  end
end
