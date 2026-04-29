# frozen_string_literal: true

require "json"
require "net/http"
require "uri"

# Calls OpenRouter chat completions API to suggest English and Chinese meanings for a vocabulary word.
class OpenRouterWordMeaningClient
  class Error < StandardError; end

  MeaningResult = Data.define(:english_meaning, :chinese_meaning)

  OPENROUTER_URI = URI("https://openrouter.ai/api/v1/chat/completions")
  DEFAULT_MODEL = "deepseek/deepseek-v4-pro"

  # @param requester [#call(String)] optional callable(body_json) -> response object with #code and #body
  def initialize(api_key: ENV.fetch("OPENROUTER_API_KEY", nil), model: nil, requester: nil)
    @api_key = api_key
    @model = model.presence || ENV["OPENROUTER_MODEL"].presence || DEFAULT_MODEL
    @requester = requester
  end

  # @param word [String] English lemma to look up
  # @return [MeaningResult]
  def lookup(word)
    raise Error, "OPENROUTER_API_KEY is not set" if @api_key.to_s.strip.empty?

    trimmed = word.to_s.strip
    raise Error, "word is blank" if trimmed.empty?

    payload = build_payload(trimmed)
    body_json = JSON.generate(payload)
    response = perform_request(body_json)

    unless response.code.to_i.between?(200, 299)
      snippet = response.body.to_s.byteslice(0, 500)
      raise Error, "OpenRouter request failed (#{response.code}): #{snippet}"
    end

    parse_meaning_from_response(response.body)
  end

  private

  def build_payload(word)
    {
      model: @model,
      messages: [
        {
          role: "user",
          content: <<~PROMPT.squish
            For the English word "#{word.gsub(/\"/, "'")}", reply with ONLY a single JSON object (no markdown, no code fences) with exactly two string keys:
            "english_meaning" — a concise English definition or gloss suitable for a learner;
            "chinese_meaning" — a concise Chinese translation or gloss for the same sense.
            Example shape: {"english_meaning":"...","chinese_meaning":"..."}
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

  def parse_meaning_from_response(response_body)
    outer = JSON.parse(response_body)
    content = outer.dig("choices", 0, "message", "content")
    raise Error, "OpenRouter response missing message content" if content.to_s.strip.empty?

    inner = JSON.parse(content.strip)
    en = inner["english_meaning"]
    zh = inner["chinese_meaning"]
    raise Error, "OpenRouter JSON missing english_meaning or chinese_meaning" if en.to_s.strip.empty? || zh.to_s.strip.empty?

    MeaningResult.new(english_meaning: en.to_s.strip, chinese_meaning: zh.to_s.strip)
  rescue JSON::ParserError => e
    raise Error, "Invalid JSON from OpenRouter: #{e.message}"
  end
end
