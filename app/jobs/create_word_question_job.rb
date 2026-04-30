# frozen_string_literal: true

class CreateWordQuestionJob < ApplicationJob
  queue_as :default

  def perform(word_id)
    word = Word.find_by(id: word_id)
    return unless word

    FindOrCreateWordQuestion.new.call(word: word)
  rescue Llm::OpenRouterSimilarWordsClient::Error => e
    Rails.logger.error("CreateWordQuestionJob LLM error for word_id=#{word_id}: #{e.class}: #{e.message}")
  end
end
# frozen_string_literal: true

class CreateWordQuestionJob < ApplicationJob
  queue_as :default

  def perform(word_id)
    word = Word.find_by(id: word_id)
    return unless word

    FindOrCreateWordQuestion.new.call(word: word)
  rescue Llm::OpenRouterSimilarWordsClient::Error => e
    Rails.logger.error("CreateWordQuestionJob LLM error for word_id=#{word_id}: #{e.class}: #{e.message}")
  end
end
