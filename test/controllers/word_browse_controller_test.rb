# frozen_string_literal: true

require "test_helper"

class WordBrowseControllerTest < ActionDispatch::IntegrationTest
  setup do
    @apple = Word.create!(word: "apple", english_meaning: "a fruit", chinese_meaning: "苹果")
    @banana = Word.create!(word: "banana", english_meaning: "a fruit", chinese_meaning: "香蕉")
  end

  test "index shows first word when no word_id given" do
    get word_browse_path

    assert_response :success
    assert_select "h1", "Browse Words"
    assert_select "h2", @apple.word
  end

  test "index shows requested word" do
    get word_browse_path(word_id: @banana.id)

    assert_response :success
    assert_select "h2", @banana.word
  end

  test "index shows word detail: english meaning, chinese meaning, pronunciation" do
    get word_browse_path(word_id: @apple.id)

    assert_response :success
    assert_select "dd", /#{Regexp.escape(@apple.english_meaning)}/
    assert_select "dd", /#{Regexp.escape(@apple.chinese_meaning)}/
  end

  test "index shows remember and skip buttons" do
    get word_browse_path(word_id: @apple.id)

    assert_response :success
    assert_select "form[action=?]", word_browse_record_path do
      assert_select "input[name='word_id'][value='#{@apple.id}']", count: 1
      assert_select "button[name='is_correct'][value='true']"
      assert_select "button[name='is_correct'][value='false']"
    end
    assert_select "a[href*='word_browse']", /skip/i
  end

  test "index shows progress counter" do
    get word_browse_path(word_id: @apple.id)

    assert_response :success
    assert_select "*", /1.*2|Word 1/i
  end

  test "index shows completion screen when no words exist" do
    Word.destroy_all
    get word_browse_path

    assert_response :success
    assert_select "h2", /no words|all done/i
  end

  test "create_record saves WordSelfRecallRecord and redirects to next word" do
    assert_difference -> { WordSelfRecallRecord.count }, +1 do
      post word_browse_record_path, params: {
        word_id: @apple.id,
        next_word_id: @banana.id,
        is_correct: "true"
      }
    end

    record = WordSelfRecallRecord.last
    assert_equal @apple.id, record.word_id
    assert record.is_correct
    assert_redirected_to word_browse_path(word_id: @banana.id)
  end

  test "create_record with is_correct false saves and redirects" do
    assert_difference -> { WordSelfRecallRecord.count }, +1 do
      post word_browse_record_path, params: {
        word_id: @apple.id,
        next_word_id: @banana.id,
        is_correct: "false"
      }
    end

    record = WordSelfRecallRecord.last
    assert_equal false, record.is_correct
  end

  test "create_record on last word redirects to word_browse root with notice" do
    assert_difference -> { WordSelfRecallRecord.count }, +1 do
      post word_browse_record_path, params: {
        word_id: @banana.id,
        next_word_id: "",
        is_correct: "true"
      }
    end

    assert_redirected_to word_browse_path
    assert_match(/all words browsed/i, flash[:notice])
  end

  test "create_record with invalid word_id redirects back with alert" do
    assert_no_difference -> { WordSelfRecallRecord.count } do
      post word_browse_record_path, params: {
        word_id: 0,
        next_word_id: "",
        is_correct: "true"
      }
    end

    assert_redirected_to word_browse_path
    assert_match(/could not save/i, flash[:alert])
  end

  test "nav link Browse is present and active on browse page" do
    get word_browse_path

    assert_response :success
    assert_select "nav a[href=?]", word_browse_path
  end
end
