class RememberWordsController < ApplicationController
  DIRECTIONS = %w[english_to_chinese chinese_to_english].freeze

  def index
    @direction = normalized_direction
    @recalled_word_ids = recalled_word_ids
    load_progress_counts!

    if load_result_state
      return
    end

    due_words = WordsDueForRecall.call(day: Date.current)
    filtered_due_words = WordsDueForRecall.call(day: Date.current, excluding_word_ids: @recalled_word_ids)

    if @recalled_word_ids.any? && filtered_due_words.none?
      redirect_to root_path(direction: @direction), notice: pass_cleared_notice(due_words)
      return
    end

    @question = build_question(filtered_due_words.first)
    @word_question_record = WordQuestionRecord.new(word_question: @question) if @question
  end

  def today
    @today_words = TodayWordsProgress.call(day: Date.current)
    @reviewed_count = @today_words.count { |item| item[:reviewed] }
    @total_count = @today_words.size
    @pending_count = @total_count - @reviewed_count
  end

  def statistics
    @stats = RememberWordsStatistics.call(day: Date.current, days: 365)
    @heatmap_dates = @stats[:daily_review_counts].keys.sort
  end

  private

  def normalized_direction
    return params[:direction] if DIRECTIONS.include?(params[:direction])

    "english_to_chinese"
  end

  def recalled_word_ids
    params[:recalled_word_ids].to_s.split(",").filter_map do |word_id|
      parsed_id = Integer(word_id, exception: false)
      parsed_id if parsed_id&.positive?
    end.uniq
  end

  def load_result_state
    @result_record = WordQuestionRecord.includes(word_question: :similar_words).find_by(id: params[:result_record_id])
    return false unless @result_record

    @question = @result_record.word_question
    @word_question_record = @result_record
    @selected_choice_token = @result_record.picked_choice_token
    @correct_choice = @question.choices.find(&:correct)
    @next_word_path = root_path(
      direction: @direction,
      recalled_word_ids: (@recalled_word_ids + [ @question.word_id ]).uniq.join(",")
    )

    true
  end

  def result_state?
    @result_record.present?
  end
  helper_method :result_state?

  def choice_display_text(choice)
    english_to_chinese? ? choice.chinese_meaning : choice.word
  end
  helper_method :choice_display_text

  def english_to_chinese?
    @direction == "english_to_chinese"
  end
  helper_method :english_to_chinese?

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

  def load_progress_counts!
    current_due_word_ids = WordsDueForRecall.call(day: Date.current).pluck(:id)
    remembered_today_word_ids = WordQuestionRecord
      .joins(:word_question)
      .where(is_correct: true, created_at: Time.zone.today.all_day)
      .distinct
      .pluck("word_questions.word_id")
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
