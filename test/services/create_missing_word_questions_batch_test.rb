# frozen_string_literal: true

require "test_helper"
require "ostruct"

class CreateMissingWordQuestionsBatchTest < ActiveSupport::TestCase
  def triples_for(lemma)
    3.times.map do |i|
      {
        "word" => "#{lemma}_distractor_#{i}",
        "english_meaning" => "meaning #{lemma} #{i}",
        "chinese_meaning" => "义#{i}"
      }
    end
  end

  def build_batch_client(lemmas)
    inner = lemmas.map do |lemma|
      { "word" => lemma, "similar_words" => triples_for(lemma) }
    end
    outer = { "choices" => [ { "message" => { "content" => JSON.generate(inner) } } ] }
    requester = ->(_body) { OpenStruct.new(code: "200", body: JSON.generate(outer)) }
    Llm::OpenRouterSimilarWordsClient.new(api_key: "test-key", requester: requester)
  end

  test "creates word questions for words missing them in one batch" do
    lemmas = Word.where.missing(:word_questions).order(:id).limit(30).pluck(:word)
    assert lemmas.size >= 2, "fixtures should include at least two words without questions"

    client = build_batch_client(lemmas)
    service = CreateMissingWordQuestionsBatch.new(llm_client: client)

    assert_difference "WordQuestion.count", lemmas.size do
      service.call
    end

    lemmas.each do |lemma|
      word = Word.find_by!("lower(word) = ?", lemma.downcase)
      assert word.word_questions.exists?, "expected question for #{lemma}"
    end
  end
end
