# frozen_string_literal: true

require "test_helper"
require "ostruct"

class CreateBatchWordQuestionsJobTest < ActiveJob::TestCase
  def build_batch_client(lemmas)
    inner = lemmas.map do |lemma|
      {
        "word" => lemma,
        "similar_words" => 3.times.map do |i|
          {
            "word" => "#{lemma}_batch_#{i}",
            "english_meaning" => "meaning #{i}",
            "chinese_meaning" => "义#{i}"
          }
        end
      }
    end
    outer = { "choices" => [{ "message" => { "content" => JSON.generate(inner) } }] }
    requester = ->(_body) { OpenStruct.new(code: "200", body: JSON.generate(outer)) }
    Llm::OpenRouterSimilarWordsClient.new(api_key: "test-key", requester: requester)
  end

  test "creates questions for all provided word ids" do
    words = [
      Word.create!(word: "batch_job_word_1", english_meaning: "m1", chinese_meaning: "中1"),
      Word.create!(word: "batch_job_word_2", english_meaning: "m2", chinese_meaning: "中2")
    ]
    client = build_batch_client(words.map(&:word))

    original_new = Llm::OpenRouterSimilarWordsClient.method(:new)
    Llm::OpenRouterSimilarWordsClient.define_singleton_method(:new) { |*_args, **_kwargs| client }
    begin
      assert_difference("WordQuestion.count", 2) do
        CreateBatchWordQuestionsJob.perform_now(words.map(&:id))
      end
    ensure
      Llm::OpenRouterSimilarWordsClient.singleton_class.send(:define_method, :new, original_new)
    end
  end
end
