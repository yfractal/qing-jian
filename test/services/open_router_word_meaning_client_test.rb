# frozen_string_literal: true

require "test_helper"
require "ostruct"

class OpenRouterWordMeaningClientTest < ActiveSupport::TestCase
  setup do
    @api_key = "test-key"
  end

  test "lookup raises when api key is missing" do
    client = OpenRouterWordMeaningClient.new(api_key: "", requester: ->(*) { raise "should not call" })
    error = assert_raises(OpenRouterWordMeaningClient::Error) { client.lookup("cat") }
    assert_equal "OPENROUTER_API_KEY is not set", error.message
  end

  test "lookup raises when word is blank" do
    client = OpenRouterWordMeaningClient.new(api_key: @api_key, requester: ->(*) { raise "should not call" })
    error = assert_raises(OpenRouterWordMeaningClient::Error) { client.lookup("   ") }
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
    client = OpenRouterWordMeaningClient.new(api_key: @api_key, requester: ->(_body) { response })

    result = client.lookup("cat")
    assert_instance_of OpenRouterWordMeaningClient::MeaningResult, result
    assert_equal "A small carnivorous mammal.", result.english_meaning
    assert_equal "猫", result.chinese_meaning
  end

  test "lookup raises on non success status" do
    response = OpenStruct.new(code: "401", body: '{"error":"unauthorized"}')
    client = OpenRouterWordMeaningClient.new(api_key: @api_key, requester: ->(_body) { response })

    error = assert_raises(OpenRouterWordMeaningClient::Error) { client.lookup("cat") }
    assert_match(/OpenRouter request failed \(401\)/, error.message)
  end

  test "lookup raises when message content is missing" do
    outer = { "choices" => [{ "message" => { "content" => "" } }] }
    response = OpenStruct.new(code: "200", body: JSON.generate(outer))
    client = OpenRouterWordMeaningClient.new(api_key: @api_key, requester: ->(_body) { response })

    error = assert_raises(OpenRouterWordMeaningClient::Error) { client.lookup("cat") }
    assert_match(/missing message content/, error.message)
  end

  test "lookup raises when inner json is malformed" do
    outer = { "choices" => [{ "message" => { "content" => "not json" } }] }
    response = OpenStruct.new(code: "200", body: JSON.generate(outer))
    client = OpenRouterWordMeaningClient.new(api_key: @api_key, requester: ->(_body) { response })

    error = assert_raises(OpenRouterWordMeaningClient::Error) { client.lookup("cat") }
    assert_match(/Invalid JSON from OpenRouter/, error.message)
  end

  test "lookup raises when inner json missing keys" do
    outer = { "choices" => [{ "message" => { "content" => '{"english_meaning":"x"}' } }] }
    response = OpenStruct.new(code: "200", body: JSON.generate(outer))
    client = OpenRouterWordMeaningClient.new(api_key: @api_key, requester: ->(_body) { response })

    error = assert_raises(OpenRouterWordMeaningClient::Error) { client.lookup("cat") }
    assert_match(/missing english_meaning or chinese_meaning/, error.message)
  end

  test "default model is deepseek v4 pro when env model unset" do
    captured = nil
    response = OpenStruct.new(code: "200", body: JSON.generate(
      "choices" => [{ "message" => { "content" => '{"english_meaning":"a","chinese_meaning":"b"}' } }]
    ))
    old_model = ENV.fetch("OPENROUTER_MODEL", nil)
    ENV.delete("OPENROUTER_MODEL")
    client = OpenRouterWordMeaningClient.new(
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
end
