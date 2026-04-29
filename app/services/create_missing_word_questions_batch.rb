# frozen_string_literal: true

# Fills WordQuestion rows for words that have none yet, using one batched LLM call per run.
class CreateMissingWordQuestionsBatch
  BATCH_SIZE = 30

  def initialize(llm_client: Llm::OpenRouterSimilarWordsClient.new)
    @llm_client = llm_client
  end

  def call
    words = Word.where.missing(:word_questions).order(:id).limit(BATCH_SIZE).to_a
    return if words.empty?

    lemmas = words.map(&:word)
    similar_by_target = @llm_client.similar_words_for_words(lemmas)

    words.each { |word| create_question_for_word(word, similar_by_target) }
  rescue Llm::OpenRouterSimilarWordsClient::Error => e
    Rails.logger.error("CreateMissingWordQuestionsBatch LLM error: #{e.class}: #{e.message}")
  end

  private

  def create_question_for_word(word, similar_by_target)
    return if word.word_questions.exists?

    triples = similar_by_target[word.word]
    unless triples&.size == 3
      Rails.logger.warn("CreateMissingWordQuestionsBatch skipping word_id=#{word.id}: missing similar words in batch response")
      return
    end

    ActiveRecord::Base.transaction do
      word.reload
      return if word.word_questions.exists?

      similar_word_records = triples.map do |result|
        # Reuses FindOrCreateWordQuestion.find_or_create_word_for_similar_result to persist distractors.
        FindOrCreateWordQuestion.find_or_create_word_for_similar_result(result)
      end

      question = word.word_questions.build
      similar_word_records.each { |similar_word_record| question.similar_words.build(word: similar_word_record) }
      question.save!
    end
  rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique => e
    Rails.logger.warn("CreateMissingWordQuestionsBatch skipped word_id=#{word&.id}: #{e.class}: #{e.message}")
  end
end
