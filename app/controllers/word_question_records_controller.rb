class WordQuestionRecordsController < ApplicationController
  DIRECTIONS = %w[english_to_chinese chinese_to_english].freeze

  def create
    question = WordQuestion.find(record_params[:word_question_id])
    picked_word = Word.find(record_params[:picked_word_id])

    WordQuestionRecord.create!(
      word_question: question,
      picked_word: picked_word,
      is_correct: picked_word.id == question.word_id
    )

    redirect_to root_path_with_state(recalled_word_ids + [ question.word_id ]), notice: "Answer saved."
  rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotFound
    redirect_to root_path_with_state(recalled_word_ids), alert: "Could not save answer."
  end

  private

  def record_params
    params.require(:word_question_record).permit(:word_question_id, :picked_word_id)
  end

  def recalled_word_ids
    params[:recalled_word_ids].to_s.split(",").filter_map do |word_id|
      parsed_id = Integer(word_id, exception: false)
      parsed_id if parsed_id&.positive?
    end.uniq
  end

  def normalized_direction
    return params[:direction] if DIRECTIONS.include?(params[:direction])

    "english_to_chinese"
  end

  def root_path_with_state(word_ids)
    state_params = { direction: normalized_direction }
    normalized_word_ids = word_ids.uniq
    state_params[:recalled_word_ids] = normalized_word_ids.join(",") if normalized_word_ids.any?

    root_path(state_params)
  end
end
