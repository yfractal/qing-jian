module BookPlugin
  class FlashCard < ApplicationRecord
    belongs_to :book
    belongs_to :book_html
    has_one :recall_state, class_name: "BookPlugin::FlashCardRecallState", dependent: :destroy
    has_many :recall_records, class_name: "BookPlugin::FlashCardRecallRecord", dependent: :destroy

    validates :book_html_id, presence: true

    after_create :create_initial_recall_state

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

    private

    def create_initial_recall_state
      create_recall_state!(remember_times: 0, due_day: created_at.to_date)
    end
  end
end
