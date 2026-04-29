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
    # Create a fresh word with today's due date
    word = Word.create!(
      word: "test_#{Time.now.to_i}",
      english_meaning: "test word",
      chinese_meaning: "测试"
    )
    word.word_recall_state.update!(due_day: Date.current)

    get root_url

    assert_response :success
    assert_match "测试", @response.body
    assert_select "form"
    assert_select "input[type='radio'][name='word_question_record[picked_word_id]']"
  end

  test "shows no-words message when no words are due" do
    # Delete all due words by setting their due days in the future
    WordRecallState.update_all(due_day: Date.current + 100.days)

    get root_url

    assert_response :success
    assert_match "No words due today", @response.body
  end
end
