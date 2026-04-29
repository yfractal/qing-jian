class RememberWordsController < ApplicationController
  def index
    @recalled_word_ids = recalled_word_ids
    due_words = WordsDueForRecall.call(day: Date.current)
    filtered_due_words = WordsDueForRecall.call(day: Date.current, excluding_word_ids: @recalled_word_ids)

    if @recalled_word_ids.any? && filtered_due_words.none?
      redirect_to root_path, notice: pass_cleared_notice(due_words)
      return
    end

    @question = build_question(filtered_due_words.first)
    @word_question_record = WordQuestionRecord.new(word_question: @question) if @question
  end

  private

  def recalled_word_ids
    params[:recalled_word_ids].to_s.split(",").filter_map do |word_id|
      parsed_id = Integer(word_id, exception: false)
      parsed_id if parsed_id&.positive?
    end.uniq
  end

  def pass_cleared_notice(due_words)
    if due_words.exists?
      "Starting another recall pass for words still due."
    else
      "All words recalled for today."
    end
  end

  def build_question(word)
    return nil unless word

    FindOrCreateWordQuestion.new.call(word: word)
  end
end
