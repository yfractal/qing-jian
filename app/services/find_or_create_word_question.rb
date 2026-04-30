# frozen_string_literal: true

# Finds an existing WordQuestion for a word, or creates one via LLM-suggested similar words.
class FindOrCreateWordQuestion
  def initialize(llm_client: Llm::OpenRouterSimilarWordsClient.new)
    @llm_client = llm_client
  end

  # @param word [Word]
  # @return [WordQuestion]
  def call(word:)
    existing = word.word_questions.first
    return existing if existing

    similar_results = @llm_client.similar_words(word.word)

    question = word.word_questions.build
    similar_results.each do |result|
      question.similar_words.build(
        word: result.word,
        english_meaning: result.english_meaning,
        chinese_meaning: result.chinese_meaning
      )
    end
    question.save!
    question
  end
end
