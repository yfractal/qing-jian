class WordFlashRememberController < ApplicationController
  def index
    @reviewed_word_ids = reviewed_word_ids
    load_progress_counts!

    due_words = WordsDueForRecall.call(day: Date.current)
    filtered_due_words = WordsDueForRecall.call(
      day: Date.current,
      excluding_word_ids: @reviewed_word_ids
    )

    if @reviewed_word_ids.any? && filtered_due_words.none?
      redirect_to root_path, notice: pass_cleared_notice(due_words)
      return
    end

    @word = filtered_due_words.order(Arel.sql("RANDOM()")).first
    @word_self_recall_record = WordSelfRecallRecord.new(word: @word) if @word
  end

  private

  def reviewed_word_ids
    params[:reviewed_word_ids].to_s.split(",").filter_map do |word_id|
      parsed_id = Integer(word_id, exception: false)
      parsed_id if parsed_id&.positive?
    end.uniq
  end

  def pass_cleared_notice(due_words_scope)
    if due_words_scope.exists?
      "Starting another recall pass for words still due."
    else
      "All words recalled for today."
    end
  end

  def load_progress_counts!
    current_due_word_ids = WordsDueForRecall.call(day: Date.current).pluck(:id)

    remembered_from_questions = WordQuestionRecord
      .joins(:word_question)
      .where(is_correct: true, created_at: Time.zone.today.all_day)
      .distinct
      .pluck("word_questions.word_id")

    remembered_from_self = WordSelfRecallRecord
      .where(is_correct: true, created_at: Time.zone.today.all_day)
      .distinct
      .pluck(:word_id)

    remembered_today_word_ids = (remembered_from_questions + remembered_from_self).uniq
    progress_word_ids = current_due_word_ids | remembered_today_word_ids

    @remember_total_count = progress_word_ids.size
    @remembered_count = remembered_today_word_ids.size
    @remaining_count = current_due_word_ids.size
    @progress_percent = if @remember_total_count.zero?
      0
    else
      ((@remembered_count.to_f / @remember_total_count) * 100).round
    end
  end
end
