module BookPlugin
  class FlashCardRecallRecordsController < ApplicationController
    def create
      flash_card = FlashCard.find(record_params[:flash_card_id])
      record = FlashCardRecallRecord.create!(
        flash_card: flash_card,
        is_correct: ActiveModel::Type::Boolean.new.cast(record_params[:is_correct])
      )

      redirect_to remember_path_with_result(record), notice: "Flash card review saved."
    rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotFound
      redirect_to remember_path_with_state(reviewed_flash_card_ids), alert: "Could not save flash card review."
    end

    private

    def record_params
      params.require(:flash_card_recall_record).permit(:flash_card_id, :is_correct)
    end

    def reviewed_flash_card_ids
      params[:reviewed_flash_card_ids].to_s.split(",").filter_map do |flash_card_id|
        parsed_id = Integer(flash_card_id, exception: false)
        parsed_id if parsed_id&.positive?
      end.uniq
    end

    def remember_path_with_state(flash_card_ids)
      normalized_ids = flash_card_ids.uniq
      query = {}
      query[:reviewed_flash_card_ids] = normalized_ids.join(",") if normalized_ids.any?
      remember_flash_cards_path(query)
    end

    def remember_path_with_result(record)
      query = { result_record_id: record.id }
      normalized_ids = reviewed_flash_card_ids.uniq
      query[:reviewed_flash_card_ids] = normalized_ids.join(",") if normalized_ids.any?
      remember_flash_cards_path(query)
    end
  end
end
