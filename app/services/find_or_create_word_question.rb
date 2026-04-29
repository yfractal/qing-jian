# frozen_string_literal: true

# Finds an existing WordQuestion for a word, or creates one via LLM-suggested similar words.
class FindOrCreateWordQuestion
  def initialize(llm_client: OpenRouterSimilarWordsClient.new)
    @llm_client = llm_client
  end

  # @param word [Word]
  # @return [WordQuestion]
  def call(word:)
    existing = word.word_questions.first
    return existing if existing

    similar_results = @llm_client.similar_words(word.word)
    similar_word_records = similar_results.map { |result| find_or_create_word(result) }

    question = word.word_questions.build
    similar_word_records.each { |similar_word| question.similar_words.build(word: similar_word) }
    question.save!
    question
  end

  private

  def find_or_create_word(result)
    Word.find_by("lower(word) = ?", result.word.downcase) ||
      Word.create!(
        word: result.word,
        english_meaning: result.english_meaning,
        chinese_meaning: result.chinese_meaning
      )
  end
end
