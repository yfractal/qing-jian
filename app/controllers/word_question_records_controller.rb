class WordQuestionRecordsController < ApplicationController
  def create
    question = WordQuestion.find(record_params[:word_question_id])
    picked_word = Word.find(record_params[:picked_word_id])

    WordQuestionRecord.create!(
      word_question: question,
      picked_word: picked_word,
      is_correct: picked_word.id == question.word_id
    )

    redirect_to root_path_with_recalled_ids(recalled_word_ids + [ question.word_id ]), notice: "Answer saved."
  rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotFound
    redirect_to root_path_with_recalled_ids(recalled_word_ids), alert: "Could not save answer."
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

  def root_path_with_recalled_ids(word_ids)
    normalized_word_ids = word_ids.uniq
    return root_path if normalized_word_ids.empty?

    root_path(recalled_word_ids: normalized_word_ids.join(","))
  end
end
