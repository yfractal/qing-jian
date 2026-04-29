# frozen_string_literal: true

require "test_helper"
require "ostruct"
require "stringio"

class OpenRouterWordMeaningClientTest < ActiveSupport::TestCase
  setup do
    @api_key = "test-key"
  end

  test "lookup raises when api key is missing" do
    client = Llm::OpenRouterWordMeaningClient.new(api_key: "", requester: ->(*) { raise "should not call" })
    error = assert_raises(Llm::OpenRouterWordMeaningClient::Error) { client.lookup("cat") }
    assert_equal "OPENROUTER_API_KEY is not set", error.message
  end

  test "lookup raises when word is blank" do
    client = Llm::OpenRouterWordMeaningClient.new(api_key: @api_key, requester: ->(*) { raise "should not call" })
    error = assert_raises(Llm::OpenRouterWordMeaningClient::Error) { client.lookup("   ") }
    assert_equal "word is blank", error.message
  end

  test "lookup returns MeaningResult on success" do
    inner = { "english_meaning" => "A small carnivorous mammal.", "chinese_meaning" => "猫" }
    outer = {
      "choices" => [
        { "message" => { "content" => JSON.generate(inner) } }
      ]
    }
    response = OpenStruct.new(code: "200", body: JSON.generate(outer))
    client = Llm::OpenRouterWordMeaningClient.new(api_key: @api_key, requester: ->(_body) { response })

    result = client.lookup("cat")
    assert_instance_of Llm::OpenRouterWordMeaningClient::MeaningResult, result
    assert_equal "A small carnivorous mammal.", result.english_meaning
    assert_equal "猫", result.chinese_meaning
  end

  test "lookup raises on non success status" do
    response = OpenStruct.new(code: "401", body: '{"error":"unauthorized"}')
    client = Llm::OpenRouterWordMeaningClient.new(api_key: @api_key, requester: ->(_body) { response })

    error = assert_raises(Llm::OpenRouterWordMeaningClient::Error) { client.lookup("cat") }
    assert_match(/OpenRouter request failed \(401\)/, error.message)
  end

  test "lookup raises when message content is missing" do
    outer = { "choices" => [ { "message" => { "content" => "" } } ] }
    response = OpenStruct.new(code: "200", body: JSON.generate(outer))
    client = Llm::OpenRouterWordMeaningClient.new(api_key: @api_key, requester: ->(_body) { response })

    error = assert_raises(Llm::OpenRouterWordMeaningClient::Error) { client.lookup("cat") }
    assert_match(/missing message content/, error.message)
  end

  test "lookup raises when inner json is malformed" do
    outer = { "choices" => [ { "message" => { "content" => "not json" } } ] }
    response = OpenStruct.new(code: "200", body: JSON.generate(outer))
    client = Llm::OpenRouterWordMeaningClient.new(api_key: @api_key, requester: ->(_body) { response })

    error = assert_raises(Llm::OpenRouterWordMeaningClient::Error) { client.lookup("cat") }
    assert_match(/Invalid JSON from OpenRouter/, error.message)
  end

  test "lookup raises when inner json missing keys" do
    outer = { "choices" => [ { "message" => { "content" => '{"english_meaning":"x"}' } } ] }
    response = OpenStruct.new(code: "200", body: JSON.generate(outer))
    client = Llm::OpenRouterWordMeaningClient.new(api_key: @api_key, requester: ->(_body) { response })

    error = assert_raises(Llm::OpenRouterWordMeaningClient::Error) { client.lookup("cat") }
    assert_match(/missing english_meaning or chinese_meaning/, error.message)
  end

  test "default model is deepseek v4 pro when env model unset" do
    captured = nil
    response = OpenStruct.new(code: "200", body: JSON.generate(
      "choices" => [ { "message" => { "content" => '{"english_meaning":"a","chinese_meaning":"b"}' } } ]
    ))
    old_model = ENV.fetch("OPENROUTER_MODEL", nil)
    ENV.delete("OPENROUTER_MODEL")
    client = Llm::OpenRouterWordMeaningClient.new(
      api_key: @api_key,
      requester: lambda { |body|
        captured = JSON.parse(body)
        response
      }
    )

    client.lookup("x")
    assert_equal "deepseek/deepseek-v4-pro", captured["model"]
  ensure
    ENV["OPENROUTER_MODEL"] = old_model if old_model
  end

  test "batch_lookup raises when words array is empty" do
    client = Llm::OpenRouterWordMeaningClient.new(api_key: @api_key, requester: ->(*) { raise "should not call" })
    error = assert_raises(Llm::OpenRouterWordMeaningClient::Error) { client.batch_lookup([]) }
    assert_equal "words array is empty", error.message
  end

  test "batch_lookup returns BatchMeaningResult list on success" do
    inner = [
      { "word" => "cat", "english_meaning" => "A small carnivorous mammal.", "chinese_meaning" => "猫" },
      { "word" => "dog", "english_meaning" => "A domesticated carnivorous mammal.", "chinese_meaning" => "狗" }
    ]
    outer = { "choices" => [ { "message" => { "content" => JSON.generate(inner) } } ] }
    response = OpenStruct.new(code: "200", body: JSON.generate(outer))
    client = Llm::OpenRouterWordMeaningClient.new(api_key: @api_key, requester: ->(_body) { response })

    results = client.batch_lookup(%w[cat dog])
    assert_equal 2, results.size
    assert_instance_of Llm::OpenRouterWordMeaningClient::BatchMeaningResult, results.first
    assert_equal "cat", results[0].word
    assert_equal "狗", results[1].chinese_meaning
  end

  test "batch_lookup strips blanks and deduplicates words before request" do
    captured = nil
    inner = [
      { "word" => "cat", "english_meaning" => "A small carnivorous mammal.", "chinese_meaning" => "猫" }
    ]
    outer = { "choices" => [ { "message" => { "content" => JSON.generate(inner) } } ] }
    response = OpenStruct.new(code: "200", body: JSON.generate(outer))
    client = Llm::OpenRouterWordMeaningClient.new(
      api_key: @api_key,
      requester: lambda { |body|
        captured = JSON.parse(body)
        response
      }
    )

    results = client.batch_lookup(["  cat  ", "cat", nil, " "])
    assert_equal 1, results.size
    assert_match(/"cat"/, captured.dig("messages", 0, "content"))
  end

  test "batch_lookup raises on non success status" do
    response = OpenStruct.new(code: "500", body: '{"error":"server"}')
    client = Llm::OpenRouterWordMeaningClient.new(api_key: @api_key, requester: ->(_body) { response })
    error = assert_raises(Llm::OpenRouterWordMeaningClient::Error) { client.batch_lookup(["cat"]) }
    assert_match(/OpenRouter request failed \(500\)/, error.message)
  end

  test "batch_lookup raises when response content is not json array" do
    outer = { "choices" => [ { "message" => { "content" => '{"word":"cat"}' } } ] }
    response = OpenStruct.new(code: "200", body: JSON.generate(outer))
    client = Llm::OpenRouterWordMeaningClient.new(api_key: @api_key, requester: ->(_body) { response })
    error = assert_raises(Llm::OpenRouterWordMeaningClient::Error) { client.batch_lookup(["cat"]) }
    assert_match(/response is not an array/, error.message)
  end

  test "batch_lookup raises when item missing fields" do
    inner = [{ "word" => "cat", "english_meaning" => "x" }]
    outer = { "choices" => [ { "message" => { "content" => JSON.generate(inner) } } ] }
    response = OpenStruct.new(code: "200", body: JSON.generate(outer))
    client = Llm::OpenRouterWordMeaningClient.new(api_key: @api_key, requester: ->(_body) { response })
    error = assert_raises(Llm::OpenRouterWordMeaningClient::Error) { client.batch_lookup(["cat"]) }
    assert_match(/missing required fields/, error.message)
  end

  test "lookup logs request start and finish with timing metadata" do
    log_output = StringIO.new
    logger = Logger.new(log_output)
    response = OpenStruct.new(code: "200", body: JSON.generate(
      "choices" => [ { "message" => { "content" => '{"english_meaning":"a","chinese_meaning":"b"}' } } ]
    ))

    old_logger = Rails.logger
    Rails.logger = logger
    begin
      client = Llm::OpenRouterWordMeaningClient.new(api_key: @api_key, requester: ->(_body) { response })
      client.lookup("cat")
    ensure
      Rails.logger = old_logger
    end

    logs = log_output.string
    assert_match(/llm\.request\.start/, logs)
    assert_match(/model=deepseek\/deepseek-v4-pro/, logs)
    assert_match(/prompt=/, logs)
    assert_match(/llm\.request\.finish/, logs)
    assert_match(/end_time=/, logs)
    assert_match(/duration_ms=\d+/, logs)
  end
end
