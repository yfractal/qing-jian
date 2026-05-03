# frozen_string_literal: true

require "test_helper"

class WordsControllerTest < ActionDispatch::IntegrationTest
  class FakeMeaningClient
    def lookup(word)
      Llm::OpenRouterWordMeaningClient::MeaningResult.new(
        english_meaning: "Definition for #{word}",
        chinese_meaning: "释义",
        pronunciation: "/#{word}/"
      )
    end

    def batch_lookup(words)
      words.filter_map do |word|
        trimmed = word.to_s.strip
        next if trimmed.empty?

        Llm::OpenRouterWordMeaningClient::BatchMeaningResult.new(
          word: trimmed,
          english_meaning: "Definition for #{trimmed}",
          chinese_meaning: "释义",
          pronunciation: "/#{trimmed}/"
        )
      end
    end
  end

  class RaisingMeaningClient
    def lookup(_word)
      raise Llm::OpenRouterWordMeaningClient::Error, "API down"
    end
  end

  setup do
    @old_client = WordsController.meaning_client_class
    WordsController.meaning_client_class = FakeMeaningClient
    clear_enqueued_jobs
  end

  teardown do
    WordsController.meaning_client_class = @old_client
    clear_enqueued_jobs
  end

  test "should get index" do
    get words_url
    assert_response :success
    assert_select "h1", "Words"
    assert_match words(:cat).word, @response.body
  end

  test "words page marks Words nav link active" do
    get words_url

    assert_response :success
    assert_select "a.site-nav-link.is-active[aria-current='page'][href='#{words_path}']", "Words"
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
    assert_match "/hello/", @response.body
    assert_select "label", text: "Pronunciation"
    assert_select "input[name='word[pronunciation]'][value='/hello/']"
    assert_select "button[data-pronunciation-play][aria-label='Play sound']"
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

  test "create enqueues single word question job" do
    assert_enqueued_with(job: CreateWordQuestionJob) do
      post words_url, params: {
        word: {
          word: "single_enqueue_#{Time.now.to_i}",
          english_meaning: "A gloss",
          chinese_meaning: "中文"
        }
      }
    end
  end

  test "batch_lookup returns json meanings" do
    post batch_lookup_words_url, params: { words: ["cat", "dog"] }, as: :json
    assert_response :success

    body = JSON.parse(@response.body)
    assert_equal 2, body.fetch("meanings").size
    assert_equal "cat", body.fetch("meanings")[0].fetch("word")
    assert_equal "/cat/", body.fetch("meanings")[0].fetch("pronunciation")
  end

  test "batch_lookup validates words param" do
    post batch_lookup_words_url, params: {}, as: :json
    assert_response :unprocessable_entity
    assert_equal "words parameter is required", JSON.parse(@response.body).fetch("error")
  end

  test "batch_create creates multiple words and reports failures" do
    Word.create!(word: "existing_word", english_meaning: "existing", chinese_meaning: "已有")
    payload = [
      { word: "batch_word_1", english_meaning: "m1", chinese_meaning: "中1" },
      { word: "existing_word", english_meaning: "m2", chinese_meaning: "中2" },
      { word: "batch_word_2", english_meaning: "m3", chinese_meaning: "中3" }
    ]

    assert_difference("Word.count", 2) do
      post batch_create_words_url, params: { words: payload }, as: :json
    end

    assert_response :created
    body = JSON.parse(@response.body)
    assert_equal 2, body.fetch("created").size
    assert_equal 1, body.fetch("failed").size
    assert_equal "existing_word", body.fetch("failed")[0].fetch("word")
  end

  test "batch_create enqueues one batch job and no single-word jobs" do
    payload = [
      { word: "batch_enqueue_1", english_meaning: "m1", chinese_meaning: "中1" },
      { word: "batch_enqueue_2", english_meaning: "m2", chinese_meaning: "中2" }
    ]

    assert_enqueued_with(job: CreateBatchWordQuestionsJob) do
      post batch_create_words_url, params: { words: payload }, as: :json
    end

    single_jobs = enqueued_jobs.count { |job| job[:job] == CreateWordQuestionJob }
    assert_equal 0, single_jobs
  end

  test "batch_create validates empty words array" do
    post batch_create_words_url, params: { words: [] }, as: :json
    assert_response :unprocessable_entity
    assert_equal "words array cannot be empty", JSON.parse(@response.body).fetch("error")
  end

  test "batch_create persists pronunciation when provided" do
    payload = [
      { word: "audio_word_1", english_meaning: "m1", chinese_meaning: "中1", pronunciation: "/ˈɔːdi.oʊ/" }
    ]

    post batch_create_words_url, params: { words: payload }, as: :json
    assert_response :created

    created_word = Word.find_by!(word: "audio_word_1")
    assert_equal "/ˈɔːdi.oʊ/", created_word.pronunciation
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
