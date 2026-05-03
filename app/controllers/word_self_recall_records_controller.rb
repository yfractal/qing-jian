class WordSelfRecallRecordsController < ApplicationController
  def create
    word = Word.find(record_params[:word_id])
    WordSelfRecallRecord.create!(
      word: word,
      is_correct: ActiveModel::Type::Boolean.new.cast(record_params[:is_correct])
    )

    merged_ids = (reviewed_word_ids + [ word.id ]).uniq
    redirect_to word_path(
      word,
      reviewed_word_ids: merged_ids.join(","),
      flash_remember: "1"
    ),
      notice: "Review saved."
  rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotFound
    redirect_to word_flash_remember_path(flash_remember_query),
      alert: "Could not save review."
  end

  private

  def record_params
    params.require(:word_self_recall_record).permit(:word_id, :is_correct)
  end

  def reviewed_word_ids
    params[:reviewed_word_ids].to_s.split(",").filter_map do |word_id|
      parsed_id = Integer(word_id, exception: false)
      parsed_id if parsed_id&.positive?
    end.uniq
  end

  def flash_remember_query
    q = {}
    q[:reviewed_word_ids] = reviewed_word_ids.join(",") if reviewed_word_ids.any?
    q
  end
end
