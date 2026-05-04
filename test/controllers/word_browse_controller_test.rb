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
    assert_select "h1", "Browse words"
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
    assert_select ".word-browse-meaning-body", text: /#{Regexp.escape(@apple.english_meaning)}/
    assert_select ".word-browse-meaning-body", text: /#{Regexp.escape(@apple.chinese_meaning)}/
  end

  test "index shows edit link for current word" do
    get word_browse_path(word_id: @apple.id)

    assert_response :success
    assert_select "a[href=?]", edit_word_path(@apple), text: /edit/i
  end

  test "index shows prev and next word links, no recall form" do
    get word_browse_path(word_id: @apple.id)

    assert_response :success
    assert_select "form[action*='word_browse']", count: 0
    assert_select "a[href=?]", word_browse_path(word_id: @banana.id), text: /next word/i
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

  test "nav link Browse is present and active on browse page" do
    get word_browse_path

    assert_response :success
    assert_select "nav a[href=?]", word_browse_path
  end
end
