# frozen_string_literal: true

require "json"
require "net/http"
require "uri"

# Calls OpenRouter chat completions API to suggest 3 similar English words with meanings.
class OpenRouterSimilarWordsClient
  class Error < StandardError; end

  SimilarWordResult = Data.define(:word, :english_meaning, :chinese_meaning)

  OPENROUTER_URI = URI("https://openrouter.ai/api/v1/chat/completions")
  DEFAULT_MODEL = "deepseek/deepseek-v4-pro"
  REQUIRED_KEYS = %w[word english_meaning chinese_meaning].freeze

  # @param requester [#call(String)] optional callable(body_json) -> response object with #code and #body
  def initialize(api_key: ENV.fetch("OPENROUTER_API_KEY", nil), model: nil, requester: nil)
    @api_key = api_key
    @model = model.presence || ENV["OPENROUTER_MODEL"].presence || DEFAULT_MODEL
    @requester = requester
  end

  # @param word [String] English lemma to generate similar words for
  # @return [Array<SimilarWordResult>] exactly 3 results
  def similar_words(word)
    raise Error, "OPENROUTER_API_KEY is not set" if @api_key.to_s.strip.empty?

    trimmed = word.to_s.strip
    raise Error, "word is blank" if trimmed.empty?

    payload = build_payload(trimmed)
    response = perform_request(JSON.generate(payload))

    unless response.code.to_i.between?(200, 299)
      snippet = response.body.to_s.byteslice(0, 500)
      raise Error, "OpenRouter request failed (#{response.code}): #{snippet}"
    end

    parse_results_from_response(response.body)
  end

  private

  def build_payload(word)
    {
      model: @model,
      messages: [
        {
          role: "user",
          content: <<~PROMPT.squish
            For the English word "#{word.gsub(/"/, "'")}",
            reply with ONLY a raw JSON array (no markdown, no code fences) of exactly 3 similar English words.
            Each element must have exactly these string keys:
            "word" - the similar English word (lowercase lemma);
            "english_meaning" - a concise English definition suitable for a learner;
            "chinese_meaning" - a concise Chinese translation for the same sense.
            Example shape: [{"word":"...","english_meaning":"...","chinese_meaning":"..."},...]
          PROMPT
        }
      ]
    }
  end

  def perform_request(body_json)
    return @requester.call(body_json) if @requester

    Net::HTTP.start(
      OPENROUTER_URI.host,
      OPENROUTER_URI.port,
      use_ssl: OPENROUTER_URI.scheme == "https",
      open_timeout: 15,
      read_timeout: 60
    ) do |http|
      req = Net::HTTP::Post.new(OPENROUTER_URI)
      req["Content-Type"] = "application/json"
      req["Authorization"] = "Bearer #{@api_key}"
      req.body = body_json
      http.request(req)
    end
  end

  def parse_results_from_response(response_body)
    outer = JSON.parse(response_body)
    content = outer.dig("choices", 0, "message", "content")
    raise Error, "OpenRouter response missing message content" if content.to_s.strip.empty?

    inner = JSON.parse(content.strip)
    raise Error, "expected a JSON array of similar words" unless inner.is_a?(Array)
    raise Error, "expected exactly 3 similar words, got #{inner.size}" unless inner.size == 3

    inner.map do |entry|
      missing = REQUIRED_KEYS.find { |k| entry[k].to_s.strip.empty? }
      raise Error, "similar word entry missing required key: #{missing}" if missing

      SimilarWordResult.new(
        word: entry["word"].to_s.strip,
        english_meaning: entry["english_meaning"].to_s.strip,
        chinese_meaning: entry["chinese_meaning"].to_s.strip
      )
    end
  rescue JSON::ParserError => e
    raise Error, "Invalid JSON from OpenRouter: #{e.message}"
  end
end
