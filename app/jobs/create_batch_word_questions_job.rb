# frozen_string_literal: true

class CreateBatchWordQuestionsJob < ApplicationJob
  queue_as :default

  def perform(word_ids)
    words = Word.where(id: Array(word_ids)).order(:id).to_a
    words = words.reject { |word| word.word_questions.exists? }
    return if words.empty?

    similar_by_target = Llm::OpenRouterSimilarWordsClient.new.similar_words_for_words(words.map(&:word))

    words.each do |word|
      create_question_for_word(word, similar_by_target)
    end
  rescue Llm::OpenRouterSimilarWordsClient::Error => e
    Rails.logger.error("CreateBatchWordQuestionsJob LLM error: #{e.class}: #{e.message}")
  end

  private

  def create_question_for_word(word, similar_by_target)
    return if word.word_questions.exists?

    triples = similar_by_target[word.word]
    unless triples&.size == 3
      Rails.logger.warn("CreateBatchWordQuestionsJob skipping word_id=#{word.id}: missing similar words in batch response")
      return
    end

    ActiveRecord::Base.transaction do
      word.reload
      return if word.word_questions.exists?

      similar_word_records = triples.map do |result|
        FindOrCreateWordQuestion.find_or_create_word_for_similar_result(result)
      end

      question = word.word_questions.build
      similar_word_records.each { |similar_word_record| question.similar_words.build(word: similar_word_record) }
      question.save!
    end
  rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique => e
    Rails.logger.warn("CreateBatchWordQuestionsJob skipped word_id=#{word.id}: #{e.class}: #{e.message}")
  end
end
# frozen_string_literal: true

class CreateBatchWordQuestionsJob < ApplicationJob
  queue_as :default

  def perform(word_ids)
    words = Word.where(id: Array(word_ids)).order(:id).to_a
    words = words.reject { |word| word.word_questions.exists? }
    return if words.empty?

    similar_by_target = Llm::OpenRouterSimilarWordsClient.new.similar_words_for_words(words.map(&:word))

    words.each do |word|
      create_question_for_word(word, similar_by_target)
    end
  rescue Llm::OpenRouterSimilarWordsClient::Error => e
    Rails.logger.error("CreateBatchWordQuestionsJob LLM error: #{e.class}: #{e.message}")
  end

  private

  def create_question_for_word(word, similar_by_target)
    return if word.word_questions.exists?

    triples = similar_by_target[word.word]
    unless triples&.size == 3
      Rails.logger.warn("CreateBatchWordQuestionsJob skipping word_id=#{word.id}: missing similar words in batch response")
      return
    end

    ActiveRecord::Base.transaction do
      word.reload
      return if word.word_questions.exists?

      similar_word_records = triples.map do |result|
        FindOrCreateWordQuestion.find_or_create_word_for_similar_result(result)
      end

      question = word.word_questions.build
      similar_word_records.each { |similar_word_record| question.similar_words.build(word: similar_word_record) }
      question.save!
    end
  rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique => e
    Rails.logger.warn("CreateBatchWordQuestionsJob skipped word_id=#{word.id}: #{e.class}: #{e.message}")
  end
end
