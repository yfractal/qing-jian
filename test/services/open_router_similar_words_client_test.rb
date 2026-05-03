# frozen_string_literal: true

require "test_helper"
require "ostruct"
require "stringio"

class OpenRouterSimilarWordsClientTest < ActiveSupport::TestCase
  setup do
    @api_key = "test-key"
    @valid_inner = [
      { "word" => "kitten", "english_meaning" => "A young cat.", "chinese_meaning" => "小猫" },
      { "word" => "feline", "english_meaning" => "Of or relating to cats.", "chinese_meaning" => "猫科动物" },
      { "word" => "tomcat", "english_meaning" => "An uncastrated male cat.", "chinese_meaning" => "雄猫" }
    ]
    @valid_outer = {
      "choices" => [
        { "message" => { "content" => JSON.generate(@valid_inner) } }
      ]
    }
  end

  test "similar_words raises when api key is missing" do
    client = Llm::OpenRouterSimilarWordsClient.new(api_key: "", requester: ->(*) { raise "should not call" })
    error = assert_raises(Llm::OpenRouterSimilarWordsClient::Error) { client.similar_words("cat") }
    assert_equal "OPENROUTER_API_KEY is not set", error.message
  end

  test "similar_words raises when word is blank" do
    client = Llm::OpenRouterSimilarWordsClient.new(api_key: @api_key, requester: ->(*) { raise "should not call" })
    error = assert_raises(Llm::OpenRouterSimilarWordsClient::Error) { client.similar_words("   ") }
    assert_equal "word is blank", error.message
  end

  test "similar_words returns results on success" do
    response = OpenStruct.new(code: "200", body: JSON.generate(@valid_outer))
    client = Llm::OpenRouterSimilarWordsClient.new(api_key: @api_key, requester: ->(_body) { response })

    results = client.similar_words("cat")
    assert_equal 3, results.size
    assert_instance_of Llm::OpenRouterSimilarWordsClient::SimilarWordResult, results.first
    assert_equal "kitten", results[0].word
    assert_equal "A young cat.", results[0].english_meaning
    assert_equal "小猫", results[0].chinese_meaning
  end

  test "similar_words_for_words sends one request for multiple words and returns results by word" do
    inner = [
      { "word" => "cat", "similar_words" => @valid_inner },
      {
        "word" => "dog",
        "similar_words" => [
          { "word" => "puppy", "english_meaning" => "A young dog.", "chinese_meaning" => "小狗" },
          { "word" => "hound", "english_meaning" => "A hunting dog.", "chinese_meaning" => "猎犬" },
          { "word" => "canine", "english_meaning" => "A dog or doglike animal.", "chinese_meaning" => "犬科动物" }
        ]
      }
    ]
    outer = { "choices" => [ { "message" => { "content" => JSON.generate(inner) } } ] }
    captured_payloads = []
    response = OpenStruct.new(code: "200", body: JSON.generate(outer))
    client = Llm::OpenRouterSimilarWordsClient.new(
      api_key: @api_key,
      requester: ->(body) {
        captured_payloads << JSON.parse(body)
        response
      }
    )

    results_by_word = client.similar_words_for_words([ "cat", "dog" ])

    assert_equal 1, captured_payloads.size
    assert_match(/"cat"/, captured_payloads.first.dig("messages", 0, "content"))
    assert_match(/"dog"/, captured_payloads.first.dig("messages", 0, "content"))
    assert_equal [ "cat", "dog" ], results_by_word.keys
    assert_equal 3, results_by_word["cat"].size
    assert_equal "kitten", results_by_word["cat"].first.word
    assert_equal "puppy", results_by_word["dog"].first.word
  end

  test "similar_words raises on non success status" do
    response = OpenStruct.new(code: "401", body: '{"error":"unauthorized"}')
    client = Llm::OpenRouterSimilarWordsClient.new(api_key: @api_key, requester: ->(_body) { response })

    error = assert_raises(Llm::OpenRouterSimilarWordsClient::Error) { client.similar_words("cat") }
    assert_match(/OpenRouter request failed \(401\)/, error.message)
  end

  test "similar_words raises when message content is missing" do
    outer = { "choices" => [ { "message" => { "content" => "" } } ] }
    response = OpenStruct.new(code: "200", body: JSON.generate(outer))
    client = Llm::OpenRouterSimilarWordsClient.new(api_key: @api_key, requester: ->(_body) { response })

    error = assert_raises(Llm::OpenRouterSimilarWordsClient::Error) { client.similar_words("cat") }
    assert_match(/missing message content/, error.message)
  end

  test "similar_words raises when inner json is not an array" do
    outer = { "choices" => [ { "message" => { "content" => '{"word":"x"}' } } ] }
    response = OpenStruct.new(code: "200", body: JSON.generate(outer))
    client = Llm::OpenRouterSimilarWordsClient.new(api_key: @api_key, requester: ->(_body) { response })

    error = assert_raises(Llm::OpenRouterSimilarWordsClient::Error) { client.similar_words("cat") }
    assert_match(/expected a JSON array/, error.message)
  end

  test "similar_words raises when array has wrong count" do
    inner = @valid_inner.first(2)
    outer = { "choices" => [ { "message" => { "content" => JSON.generate(inner) } } ] }
    response = OpenStruct.new(code: "200", body: JSON.generate(outer))
    client = Llm::OpenRouterSimilarWordsClient.new(api_key: @api_key, requester: ->(_body) { response })

    error = assert_raises(Llm::OpenRouterSimilarWordsClient::Error) { client.similar_words("cat") }
    assert_match(/expected exactly 3 similar words/, error.message)
  end

  test "similar_words raises when an entry is missing required keys" do
    inner = [
      { "word" => "kitten", "english_meaning" => "A young cat." },
      { "word" => "feline", "english_meaning" => "...", "chinese_meaning" => "猫科动物" },
      { "word" => "tomcat", "english_meaning" => "...", "chinese_meaning" => "雄猫" }
    ]
    outer = { "choices" => [ { "message" => { "content" => JSON.generate(inner) } } ] }
    response = OpenStruct.new(code: "200", body: JSON.generate(outer))
    client = Llm::OpenRouterSimilarWordsClient.new(api_key: @api_key, requester: ->(_body) { response })

    error = assert_raises(Llm::OpenRouterSimilarWordsClient::Error) { client.similar_words("cat") }
    assert_match(/missing required key/, error.message)
  end

  test "similar_words raises when inner json is malformed" do
    outer = { "choices" => [ { "message" => { "content" => "not json" } } ] }
    response = OpenStruct.new(code: "200", body: JSON.generate(outer))
    client = Llm::OpenRouterSimilarWordsClient.new(api_key: @api_key, requester: ->(_body) { response })

    error = assert_raises(Llm::OpenRouterSimilarWordsClient::Error) { client.similar_words("cat") }
    assert_match(/Invalid JSON from OpenRouter/, error.message)
  end

  test "default model is deepseek v4 flash when env model unset" do
    captured = nil
    response = OpenStruct.new(code: "200", body: JSON.generate(@valid_outer))
    old_model = ENV.fetch("OPENROUTER_MODEL", nil)
    ENV.delete("OPENROUTER_MODEL")
    client = Llm::OpenRouterSimilarWordsClient.new(
      api_key: @api_key,
      requester: lambda { |body|
        captured = JSON.parse(body)
        response
      }
    )

    client.similar_words("x")
    assert_equal "deepseek/deepseek-v4-flash", captured["model"]
  ensure
    ENV["OPENROUTER_MODEL"] = old_model if old_model
  end

  test "similar_words logs request start and finish with timing metadata" do
    log_output = StringIO.new
    logger = Logger.new(log_output)
    response = OpenStruct.new(code: "200", body: JSON.generate(@valid_outer))

    old_logger = Rails.logger
    Rails.logger = logger
    begin
      client = Llm::OpenRouterSimilarWordsClient.new(api_key: @api_key, requester: ->(_body) { response })
      client.similar_words("cat")
    ensure
      Rails.logger = old_logger
    end

    logs = log_output.string
    assert_match(/llm\.request\.start/, logs)
    assert_match(/model=deepseek\/deepseek-v4-flash/, logs)
    assert_match(/prompt=/, logs)
    assert_match(/llm\.request\.finish/, logs)
    assert_match(/end_time=/, logs)
    assert_match(/duration_ms=\d+/, logs)
  end
end
