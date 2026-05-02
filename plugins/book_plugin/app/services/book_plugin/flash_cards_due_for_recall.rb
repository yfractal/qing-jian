# frozen_string_literal: true

module BookPlugin
  class FlashCardsDueForRecall
    RECALL_RULES = [
      { remember_times: 0, interval_days: 0 },
      { remember_times: 1, interval_days: 2 },
      { remember_times: 2, interval_days: 3 },
      { remember_times: 3, interval_days: 5 },
      { remember_times: 4, interval_days: 7 },
      { remember_times: 5, interval_days: 15 }
    ].freeze

    class << self
      def call(day: Date.current, book: nil, excluding_flash_card_ids: [])
        due_cards = FlashCard.joins(:recall_state).merge(FlashCardRecallState.where(due_day: ..day.to_date))
        due_cards = due_cards.where(book:) if book.present?

        excluded_ids = normalize_flash_card_ids(excluding_flash_card_ids)
        return due_cards if excluded_ids.empty?

        due_cards.where.not(id: excluded_ids)
      end

      def update_state_for(record)
        return unless record.correct?

        flash_card = record.flash_card
        state = FlashCardRecallState.find_or_initialize_by(flash_card: flash_card)
        state.remember_times ||= 0
        state.due_day ||= flash_card.created_at.to_date

        state.remember_times += 1
        state.due_day = next_due_day(
          flash_card: flash_card,
          last_correct_record: record,
          remember_times: state.remember_times
        )
        state.save!
      end

      private

      def normalize_flash_card_ids(flash_card_ids)
        Array(flash_card_ids).filter_map do |flash_card_id|
          parsed_id = Integer(flash_card_id, exception: false)
          parsed_id if parsed_id&.positive?
        end.uniq
      end

      def next_due_day(flash_card:, last_correct_record:, remember_times:)
        rule = RECALL_RULES.find { |recall_rule| recall_rule[:remember_times] == remember_times }
        return unless rule

        base_date = last_correct_record&.created_at&.to_date || flash_card.created_at.to_date
        base_date + rule[:interval_days].days
      end
    end
  end
end
