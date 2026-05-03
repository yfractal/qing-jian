# frozen_string_literal: true

require "json"
require "uri"

module Llm
  # Calls OpenRouter chat completions API to suggest 3 similar English words with meanings.
  class OpenRouterSimilarWordsClient
    include RequestSender

    class Error < StandardError; end

    SimilarWordResult = Data.define(:word, :english_meaning, :chinese_meaning)

    OPENROUTER_URI = URI("https://openrouter.ai/api/v1/chat/completions")
    # DEFAULT_MODEL = "deepseek/deepseek-v4-pro"
    DEFAULT_MODEL = 'deepseek/deepseek-v4-flash'
    REQUIRED_KEYS = %w[word english_meaning chinese_meaning].freeze

    # @param requester [#call(String)] optional callable(body_json) -> response object with #code and #body
    def initialize(api_key: ENV.fetch("OPENROUTER_API_KEY", nil), model: nil, requester: nil)
      @api_key = api_key
      @model = model.presence || DEFAULT_MODEL
      @requester = requester
    end

    # @param word [String] English lemma to generate similar words for
    # @return [Array<SimilarWordResult>] exactly 3 results
    def similar_words(word)
      ensure_api_key!

      trimmed = word.to_s.strip
      raise Error, "word is blank" if trimmed.empty?

      payload = build_payload(trimmed)
      response = send_request(body_json: JSON.generate(payload), model: @model, prompt: payload.dig(:messages, 0, :content))

      unless response.code.to_i.between?(200, 299)
        snippet = response.body.to_s.byteslice(0, 500)
        raise Error, "OpenRouter request failed (#{response.code}): #{snippet}"
      end

      parse_results_from_response(response.body)
    end

    # @param words [Array<String>] English lemmas (one OpenRouter request for the whole list)
    # @return [Hash<String, Array<SimilarWordResult>>] keys match the input strings (first occurrence casing kept)
    def similar_words_for_words(words)
      ensure_api_key!

      normalized = normalize_word_list(words)
      raise Error, "words is blank" if normalized.empty?

      payload = build_batch_payload(normalized)
      response = send_request(body_json: JSON.generate(payload), model: @model, prompt: payload.dig(:messages, 0, :content))

      unless response.code.to_i.between?(200, 299)
        snippet = response.body.to_s.byteslice(0, 500)
        raise Error, "OpenRouter request failed (#{response.code}): #{snippet}"
      end

      parse_batch_results_from_response(response.body, expected_words: normalized)
    end

    private

    def ensure_api_key!
      raise Error, "OPENROUTER_API_KEY is not set" if @api_key.to_s.strip.empty?
    end

    def normalize_word_list(words)
      seen = {}
      Array(words).filter_map do |raw|
        trimmed = raw.to_s.strip
        next if trimmed.empty?

        key = trimmed.downcase
        next if seen[key]

        seen[key] = true
        trimmed
      end
    end

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

    def build_batch_payload(words)
      words_json = JSON.generate(words)
      {
        model: @model,
        messages: [
          {
            role: "user",
            content: <<~PROMPT.squish
              You will generate distractor words for a vocabulary quiz.
              Target words (JSON array, in order): #{words_json}
              Reply with ONLY a raw JSON array (no markdown, no code fences).
              One element per target word, in the SAME ORDER as that input array.
              Each element must be an object with:
              "word" - the target English word (same spelling as the matching input element);
              "similar_words" - an array of exactly 3 objects, each with string keys:
              "word" - the similar English word (lowercase lemma);
              "english_meaning" - a concise English definition suitable for a learner;
              "chinese_meaning" - a concise Chinese translation for the same sense.
            PROMPT
          }
        ]
      }
    end

    def parse_results_from_response(response_body)
      inner = parse_message_content_json_value(response_body)
      raise Error, "expected a JSON array of similar words" unless inner.is_a?(Array)
      raise Error, "expected exactly 3 similar words, got #{inner.size}" unless inner.size == 3

      inner.map { |entry| similar_word_result_from_entry(entry) }
    end

    def parse_batch_results_from_response(response_body, expected_words:)
      inner = parse_message_content_json_value(response_body)
      raise Error, "expected a JSON array of batch results" unless inner.is_a?(Array)
      unless inner.size == expected_words.size
        raise Error, "expected #{expected_words.size} batch results, got #{inner.size}"
      end

      expected_words.each_with_index.with_object({}) do |(target, index), acc|
        item = inner[index]
        raise Error, "batch result at index #{index} must be an object" unless item.is_a?(Hash)

        returned = item["word"].to_s.strip
        unless returned.casecmp?(target)
          raise Error, "batch word mismatch at index #{index}: expected #{target.inspect}, got #{returned.inspect}"
        end

        similar = item["similar_words"]
        raise Error, "similar_words must be an array at index #{index}" unless similar.is_a?(Array)
        raise Error, "expected exactly 3 similar words at index #{index}, got #{similar.size}" unless similar.size == 3

        acc[target] = similar.map { |entry| similar_word_result_from_entry(entry) }
      end
    end

    def parse_message_content_json_value(response_body)
      outer = JSON.parse(response_body)
      content = outer.dig("choices", 0, "message", "content")
      raise Error, "OpenRouter response missing message content" if content.to_s.strip.empty?

      JSON.parse(content.strip)
    rescue JSON::ParserError => e
      raise Error, "Invalid JSON from OpenRouter: #{e.message}"
    end

    def similar_word_result_from_entry(entry)
      raise Error, "similar word entry must be an object" unless entry.is_a?(Hash)

      missing = REQUIRED_KEYS.find { |k| entry[k].to_s.strip.empty? }
      raise Error, "similar word entry missing required key: #{missing}" if missing

      SimilarWordResult.new(
        word: entry["word"].to_s.strip,
        english_meaning: entry["english_meaning"].to_s.strip,
        chinese_meaning: entry["chinese_meaning"].to_s.strip
      )
    end
  end
end
