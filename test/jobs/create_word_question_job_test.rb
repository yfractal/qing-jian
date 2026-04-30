# frozen_string_literal: true

require "test_helper"
require "ostruct"

class CreateWordQuestionJobTest < ActiveJob::TestCase
  def build_client_for(lemma)
    inner = 3.times.map do |i|
      {
        "word" => "#{lemma}_single_#{i}",
        "english_meaning" => "meaning #{i}",
        "chinese_meaning" => "义#{i}"
      }
    end
    outer = { "choices" => [{ "message" => { "content" => JSON.generate(inner) } }] }
    requester = ->(_body) { OpenStruct.new(code: "200", body: JSON.generate(outer)) }
    Llm::OpenRouterSimilarWordsClient.new(api_key: "test-key", requester: requester)
  end

  test "creates a question for word id" do
    word = Word.create!(word: "single_job_word", english_meaning: "m", chinese_meaning: "中")
    client = build_client_for(word.word)

    original_new = Llm::OpenRouterSimilarWordsClient.method(:new)
    Llm::OpenRouterSimilarWordsClient.define_singleton_method(:new) { |*_args, **_kwargs| client }
    begin
      assert_difference("WordQuestion.count", 1) do
        CreateWordQuestionJob.perform_now(word.id)
      end
    ensure
      Llm::OpenRouterSimilarWordsClient.singleton_class.send(:define_method, :new, original_new)
    end
  end
end
