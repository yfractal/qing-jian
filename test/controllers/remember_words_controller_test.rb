# frozen_string_literal: true

require "test_helper"

class RememberWordsControllerTest < ActionDispatch::IntegrationTest
  test "root renders remember words index" do
    get root_url
    assert_response :success
    assert_select "h1", "Remember words"
  end

  test "shows add new word button" do
    get root_url
    assert_response :success
    assert_select "a", "Add new word"
  end

  test "renders question form when question is available" do
    WordRecallState.update_all(due_day: Date.current + 100.days)
    word = create_due_word!("test")
    create_question_for!(word)

    get root_url

    assert_response :success
    assert_select "h2", word.chinese_meaning
    assert_select "form"
    assert_select "input[type='radio'][name='word_question_record[picked_word_id]']"
  end

  test "filters recalled word ids from the current pass" do
    WordRecallState.update_all(due_day: Date.current + 100.days)
    first_word = create_due_word!("first")
    second_word = create_due_word!("second")
    create_question_for!(first_word)
    create_question_for!(second_word)

    get root_url(recalled_word_ids: first_word.id.to_s)

    assert_response :success
    assert_no_match first_word.chinese_meaning, @response.body
    assert_match second_word.chinese_meaning, @response.body
  end

  test "clears recalled word state when filtered pass is exhausted but words are still due" do
    WordRecallState.update_all(due_day: Date.current + 100.days)
    word = create_due_word!("retry")
    create_question_for!(word)

    get root_url(recalled_word_ids: word.id.to_s)

    assert_redirected_to root_url
    assert_equal "Starting another recall pass for words still due.", flash[:notice]
  end

  test "clears stale recalled word state when no words are due" do
    WordRecallState.update_all(due_day: Date.current + 100.days)
    word = create_due_word!("finished")
    create_question_for!(word)
    word.word_recall_state.update!(due_day: Date.current + 100.days)

    get root_url(recalled_word_ids: word.id.to_s)

    assert_redirected_to root_url
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

  test "shows congratulations message when no words are due" do
    WordRecallState.update_all(due_day: Date.current + 100.days)

    get root_url

    assert_response :success
    assert_match "Congratulations! You have recalled all words due today.", @response.body
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
      choice_word = Word.create!(
        word: "#{word.word}_choice_#{index}_#{SecureRandom.hex(4)}",
        english_meaning: "choice #{index}",
        chinese_meaning: "choice #{index}"
      )
      choice_word.word_recall_state.update!(due_day: Date.current + 100.days)
      question.similar_words.build(word: choice_word)
    end

    question.save!
    question
  end
end
