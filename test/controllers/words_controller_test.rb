# frozen_string_literal: true

require "test_helper"

class WordsControllerTest < ActionDispatch::IntegrationTest
  class FakeMeaningClient
    def lookup(word)
      OpenRouterWordMeaningClient::MeaningResult.new(
        english_meaning: "Definition for #{word}",
        chinese_meaning: "释义"
      )
    end
  end

  class RaisingMeaningClient
    def lookup(_word)
      raise OpenRouterWordMeaningClient::Error, "API down"
    end
  end

  setup do
    @old_client = WordsController.meaning_client_class
    WordsController.meaning_client_class = FakeMeaningClient
  end

  teardown do
    WordsController.meaning_client_class = @old_client
  end

  test "should get index" do
    get words_url
    assert_response :success
    assert_select "h1", "Words"
    assert_match words(:cat).word, @response.body
  end

  test "should get new" do
    get new_word_url
    assert_response :success
    assert_select "h1", "New word"
  end

  test "lookup fills form" do
    post lookup_words_url, params: { english_word: "hello" }
    assert_response :success
    assert_match "Definition for hello", @response.body
    assert_match "释义", @response.body
  end

  test "lookup with blank word shows error" do
    post lookup_words_url, params: { english_word: "   " }
    assert_response :unprocessable_entity
    assert_match "Please enter an English word", @response.body
  end

  test "lookup shows error when client raises" do
    WordsController.meaning_client_class = RaisingMeaningClient
    post lookup_words_url, params: { english_word: "x" }
    assert_response :unprocessable_entity
    assert_match "API down", @response.body
  end

  test "should create word" do
    assert_difference("Word.count") do
      post words_url, params: {
        word: {
          word: "unique_word_#{Time.now.to_i}",
          english_meaning: "A gloss",
          chinese_meaning: "中文"
        }
      }
    end
    assert_redirected_to word_url(Word.last)
    follow_redirect!
    assert_response :success
  end

  test "should not create word with invalid params" do
    assert_no_difference("Word.count") do
      post words_url, params: {
        word: {
          word: "",
          english_meaning: "",
          chinese_meaning: ""
        }
      }
    end
    assert_response :unprocessable_entity
  end

  test "should show word" do
    get word_url(words(:cat))
    assert_response :success
    assert_match words(:cat).word, @response.body
  end

  test "should get edit" do
    get edit_word_url(words(:cat))
    assert_response :success
  end

  test "should update word" do
    w = words(:cat)
    patch word_url(w), params: {
      word: {
        word: w.word,
        english_meaning: "Updated gloss",
        chinese_meaning: w.chinese_meaning
      }
    }
    assert_redirected_to word_url(w)
    assert_equal "Updated gloss", w.reload.english_meaning
  end

  test "should destroy word" do
    w = words(:bird)
    assert_difference("Word.count", -1) do
      delete word_url(w)
    end
    assert_redirected_to words_url
  end
end
