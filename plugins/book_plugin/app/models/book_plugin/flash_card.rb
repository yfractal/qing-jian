module BookPlugin
  class FlashCard < ApplicationRecord
    belongs_to :book
    belongs_to :book_html

    validates :book_html_id, presence: true

    # Items may be plain strings (one per line in the form) or hashes from the preview picker (JSON).
    def items_to_remember_as_form_text
      items = items_to_remember
      return "" if items.blank?

      if items.all? { |e| e.is_a?(String) }
        items.join("\n")
      else
        items.to_json
      end
    end
  end
end
