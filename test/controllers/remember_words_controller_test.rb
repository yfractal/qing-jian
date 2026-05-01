# frozen_string_literal: true

require "test_helper"

class RememberWordsControllerTest < ActionDispatch::IntegrationTest
  include ActiveSupport::Testing::TimeHelpers

  test "root renders remember words index" do
    get root_url
    assert_response :success
    assert_select "h1", "Remember Words"
  end

  test "shows add new word button" do
    get root_url
    assert_response :success
    assert_select "a", "Add new word"
  end

  test "progress ignores recalled_word_ids when no correct record exists today" do
    WordRecallState.update_all(due_day: Date.current + 100.days)
    WordQuestionRecord.delete_all
    first_word = create_due_word!("progress_first")
    second_word = create_due_word!("progress_second")
    create_question_for!(first_word)
    create_question_for!(second_word)

    get root_url(recalled_word_ids: first_word.id.to_s)

    assert_response :success
    assert_select ".remember-progress-card"
    assert_select ".remember-progress-main", text: /Remembered 0 \/ 2/
    assert_select ".remember-progress-meta", text: /Need to remember 2/
  end

  test "progress includes remembered-today words after due_day advances" do
    travel_to Time.zone.local(2026, 5, 1, 12, 0, 0) do
      WordRecallState.update_all(due_day: Date.current + 100.days)
      WordQuestionRecord.delete_all
      remembered_word = create_due_word!("remembered_today")
      still_due_word = create_due_word!("still_due_today")
      remembered_question = create_question_for!(remembered_word)
      create_question_for!(still_due_word)

      WordQuestionRecord.create!(
        word_question: remembered_question,
        picked_choice_token: "word:#{remembered_word.id}",
        picked_choice_word: remembered_word.word,
        is_correct: true,
        created_at: Time.zone.now
      )

      get root_url

      assert_response :success
      assert_equal Date.current + 2.days, remembered_word.reload.word_recall_state.due_day
      assert_select ".remember-progress-main", text: /Remembered 1 \/ 2/
      assert_select ".remember-progress-meta", text: /Need to remember 1/
    end
  end

  test "renders question form when question is available" do
    WordRecallState.update_all(due_day: Date.current + 100.days)
    word = create_due_word!("test")
    word.update!(pronunciation: "/test/")
    create_question_for!(word)

    get root_url

    assert_response :success
    assert_select "h2", word.word
    assert_select ".question-audio-word", word.word
    assert_select ".question-audio-pronunciation", "/test/"
    assert_select "button[data-pronunciation-play][data-word-text='#{word.word}'][aria-label='Play sound']"
    assert_select "form"
    assert_select "input[type='radio'][name='word_question_record[picked_choice]']"
  end

  test "defaults to english_to_chinese direction" do
    WordRecallState.update_all(due_day: Date.current + 100.days)
    word = create_due_word!("default_direction")
    create_question_for!(word)

    get root_url

    assert_response :success
    assert_select "input[type='radio'][name='direction'][value='english_to_chinese'][checked='checked']"
    assert_select "p", "Choose the correct Chinese meaning."
    assert_select "h2", word.word
  end

  test "supports chinese_to_english direction from params" do
    WordRecallState.update_all(due_day: Date.current + 100.days)
    word = create_due_word!("explicit_direction")
    word.update!(pronunciation: "/explicit/")
    create_question_for!(word)

    get root_url(direction: "chinese_to_english")

    assert_response :success
    assert_select "input[type='radio'][name='direction'][value='chinese_to_english'][checked='checked']"
    assert_select "p", "Choose the correct English word."
    assert_select "h2", word.chinese_meaning
    assert_select ".question-audio-word", word.word
    assert_select ".question-audio-pronunciation", "/explicit/"
    assert_select "button[data-pronunciation-play][data-word-text='#{word.word}'][aria-label='Play sound']"
  end

  test "falls back to english_to_chinese for invalid direction" do
    WordRecallState.update_all(due_day: Date.current + 100.days)
    word = create_due_word!("invalid_direction")
    create_question_for!(word)

    get root_url(direction: "invalid")

    assert_response :success
    assert_select "input[type='radio'][name='direction'][value='english_to_chinese'][checked='checked']"
    assert_select "h2", word.word
  end

  test "filters recalled word ids from the current pass" do
    WordRecallState.update_all(due_day: Date.current + 100.days)
    first_word = create_due_word!("first")
    second_word = create_due_word!("second")
    create_question_for!(first_word)
    create_question_for!(second_word)

    get root_url(recalled_word_ids: first_word.id.to_s)

    assert_response :success
    assert_select "h2", second_word.word
  end

  test "clears recalled word state when filtered pass is exhausted but words are still due" do
    WordRecallState.update_all(due_day: Date.current + 100.days)
    word = create_due_word!("retry")
    create_question_for!(word)

    get root_url(recalled_word_ids: word.id.to_s)

    assert_redirected_to root_url(direction: "english_to_chinese")
    assert_equal "Starting another recall pass for words still due.", flash[:notice]
  end

  test "preserves chinese_to_english direction when clearing filtered pass state" do
    WordRecallState.update_all(due_day: Date.current + 100.days)
    word = create_due_word!("retry_chinese_to_english")
    create_question_for!(word)

    get root_url(recalled_word_ids: word.id.to_s, direction: "chinese_to_english")

    assert_redirected_to root_url(direction: "chinese_to_english")
  end

  test "clears stale recalled word state when no words are due" do
    WordRecallState.update_all(due_day: Date.current + 100.days)
    word = create_due_word!("finished")
    create_question_for!(word)
    word.word_recall_state.update!(due_day: Date.current + 100.days)

    get root_url(recalled_word_ids: word.id.to_s)

    assert_redirected_to root_url(direction: "english_to_chinese")
    assert_equal "All words recalled for today.", flash[:notice]
  end

  test "includes current recalled word ids in the answer form" do
    WordRecallState.update_all(due_day: Date.current + 100.days)
    first_word = create_due_word!("answered")
    second_word = create_due_word!("visible")
    create_question_for!(first_word)
    create_question_for!(second_word)

    get root_url(recalled_word_ids: first_word.id.to_s)

    assert_response :success
    assert_select "input[type='hidden'][name='recalled_word_ids'][value='#{first_word.id}']"
  end

  test "includes current direction in answer form submission" do
    WordRecallState.update_all(due_day: Date.current + 100.days)
    word = create_due_word!("carry_direction")
    create_question_for!(word)

    get root_url(direction: "chinese_to_english")

    assert_response :success
    assert_select "input[type='hidden'][name='direction'][value='chinese_to_english']"
  end

  test "renders correct feedback state for a saved correct answer" do
    WordRecallState.update_all(due_day: Date.current + 100.days)
    word = create_due_word!("correct_feedback")
    question = create_question_for!(word)
    record = WordQuestionRecord.create!(
      word_question: question,
      picked_choice_token: "word:#{word.id}",
      picked_choice_word: word.word,
      is_correct: true
    )

    get root_url(result_record_id: record.id)

    assert_response :success
    assert_select ".feedback-panel.feedback-panel-correct", text: /Correct/
    assert_select ".choice-card.choice-correct", text: /#{Regexp.escape(word.chinese_meaning)}/
    assert_select "a", "Next word"
  end

  test "renders incorrect feedback state with the correct answer" do
    WordRecallState.update_all(due_day: Date.current + 100.days)
    word = create_due_word!("incorrect_feedback")
    question = create_question_for!(word)
    wrong_choice = question.similar_words.first
    record = WordQuestionRecord.create!(
      word_question: question,
      picked_choice_token: "similar_word:#{wrong_choice.id}",
      picked_choice_word: wrong_choice.word,
      is_correct: false
    )

    get root_url(result_record_id: record.id)

    assert_response :success
    assert_select ".feedback-panel.feedback-panel-incorrect", text: /Not quite/
    assert_select ".answer-reveal", text: /Correct answer: #{word.chinese_meaning}/
    assert_select ".choice-card.choice-selected-wrong", text: /#{Regexp.escape(wrong_choice.chinese_meaning)}/
    assert_select ".choice-card.choice-correct", text: /#{Regexp.escape(word.chinese_meaning)}/
  end

  test "result state preserves chinese_to_english answer display" do
    WordRecallState.update_all(due_day: Date.current + 100.days)
    word = create_due_word!("chinese_feedback")
    question = create_question_for!(word)
    record = WordQuestionRecord.create!(
      word_question: question,
      picked_choice_token: "word:#{word.id}",
      picked_choice_word: word.word,
      is_correct: true
    )

    get root_url(direction: "chinese_to_english", result_record_id: record.id)

    assert_response :success
    assert_select "h2", word.chinese_meaning
    assert_select ".choice-card.choice-correct", text: /#{Regexp.escape(word.word)}/
  end

  test "next word link appends answered word id to recalled word ids" do
    WordRecallState.update_all(due_day: Date.current + 100.days)
    previous_word = create_due_word!("previous_recalled")
    word = create_due_word!("next_link")
    question = create_question_for!(word)
    record = WordQuestionRecord.create!(
      word_question: question,
      picked_choice_token: "word:#{word.id}",
      picked_choice_word: word.word,
      is_correct: true
    )

    get root_url(recalled_word_ids: previous_word.id.to_s, result_record_id: record.id)

    expected_path = root_path(
      direction: "english_to_chinese",
      recalled_word_ids: "#{previous_word.id},#{word.id}"
    )
    next_word_link = nil
    assert_select "a", "Next word" do |elements|
      next_word_link = elements.first
    end
    assert_equal expected_path, next_word_link["href"]
  end

  test "invalid result record id falls back to normal question state" do
    WordRecallState.update_all(due_day: Date.current + 100.days)
    word = create_due_word!("invalid_result")
    create_question_for!(word)

    get root_url(result_record_id: "999999")

    assert_response :success
    assert_select "h2", word.word
    assert_select ".feedback-panel", count: 0
  end

  test "shows completion card when no words are due" do
    WordRecallState.update_all(due_day: Date.current + 100.days)

    get root_url

    assert_response :success
    assert_select ".completion-card"
    assert_match "All caught up", @response.body
    assert_match "You have recalled all words due today.", @response.body
  end

  test "today page lists word, pronunciation, chinese meaning, and review status" do
    WordRecallState.update_all(due_day: Date.current + 100.days)
    reviewed_word = create_due_word!("reviewed_item")
    pending_word = create_due_word!("pending_item")
    reviewed_word.update!(pronunciation: "/reviewed/")
    pending_word.update!(pronunciation: "/pending/")
    reviewed_question = create_question_for!(reviewed_word)

    WordQuestionRecord.create!(
      word_question: reviewed_question,
      picked_choice_token: "word:#{reviewed_word.id}",
      picked_choice_word: reviewed_word.word,
      is_correct: true,
      created_at: Time.zone.now
    )

    get today_words_url

    assert_response :success
    assert_select "h1", "Today Words"
    assert_select ".today-word-item", minimum: 2
    assert_select ".today-word-status-reviewed", text: /Reviewed/
    assert_select ".today-word-status-pending", text: /Not reviewed/
    assert_match reviewed_word.chinese_meaning, @response.body
    assert_match "/reviewed/", @response.body
  end

  test "remember progress card links to today words page" do
    get root_url

    assert_response :success
    assert_select "a.remember-progress-card[href='#{today_words_path}']"
    assert_select "a.remember-progress-card", text: /Remembered \d+ \/ \d+/
  end

  test "statistics page renders summary cards and heatmap" do
    WordRecallState.update_all(due_day: Date.current + 100.days)
    word = create_due_word!("stats_word")
    word.word_recall_state.update!(remember_times: 6)
    question = create_question_for!(word)
    WordQuestionRecord.create!(
      word_question: question,
      picked_choice_token: "word:#{word.id}",
      picked_choice_word: word.word,
      is_correct: true,
      created_at: Time.zone.now
    )

    get statistics_words_url

    assert_response :success
    assert_select "h1", "Statistics"
    assert_match(/Today \d+ reviews/, @response.body)
    assert_select ".statistics-summary-card", minimum: 4
    assert_select ".statistics-heatmap"
    assert_select ".statistics-label", text: /remember_times >= 6/
    assert_select ".statistics-label", text: /Reviews in last 7 days/
    assert_select ".statistics-label", text: /Active review days in last 30 days/
    assert_select ".statistics-heatmap-cell", minimum: RememberWordsStatistics::HEATMAP_GRID_DAYS
    assert_select ".statistics-heatmap-grid .statistics-heatmap-cell[data-tooltip]", minimum: RememberWordsStatistics::HEATMAP_GRID_DAYS
    assert_select ".statistics-heatmap-grid .statistics-heatmap-cell[title]", count: 0
  end

  private

  def create_due_word!(name)
    Word.create!(
      word: "#{name}_#{SecureRandom.hex(4)}",
      english_meaning: "#{name} english",
      chinese_meaning: "#{name} chinese"
    ).tap do |word|
      word.word_recall_state.update!(due_day: Date.current)
    end
  end

  def create_question_for!(word)
    question = WordQuestion.new(word: word)

    3.times do |index|
      question.similar_words.build(
        word: "#{word.word}_choice_#{index}_#{SecureRandom.hex(4)}",
        english_meaning: "choice #{index}",
        chinese_meaning: "choice #{index}"
      )
    end

    question.save!
    question
  end
end
