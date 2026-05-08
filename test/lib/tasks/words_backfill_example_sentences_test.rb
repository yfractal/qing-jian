# frozen_string_literal: true

require "test_helper"
require "rake"

class WordsBackfillExampleSentencesTaskTest < ActiveSupport::TestCase
  setup do
    Rails.application.load_tasks if Rake::Task.tasks.empty?
    @task = Rake::Task["words:backfill_example_sentences"]
    @task.reenable
  end

  test "backfills missing example sentences in batches" do
    suffix = Time.now.to_i.to_s
    Word.create!(word: "empty_cat_#{suffix}", english_meaning: "m", chinese_meaning: "中")
    Word.create!(word: "empty_dog_#{suffix}", english_meaning: "m", chinese_meaning: "中")
    Word.create!(word: "has_sentence_#{suffix}", english_meaning: "m", chinese_meaning: "中", example_sentence: "Already set.")

    fake_client = Class.new do
      def batch_lookup(words)
        words.map do |w|
          Llm::OpenRouterWordMeaningClient::BatchMeaningResult.new(
            word: w,
            english_meaning: "m",
            chinese_meaning: "中",
            pronunciation: "/x/",
            example_sentence: "Simple sentence for #{w}."
          )
        end
      end
    end.new

    original_new = Llm::OpenRouterWordMeaningClient.method(:new)
    Llm::OpenRouterWordMeaningClient.define_singleton_method(:new) { |*_args, **_kwargs| fake_client }
    begin
      @task.invoke("2")
    ensure
      Llm::OpenRouterWordMeaningClient.singleton_class.send(:define_method, :new, original_new)
    end

    assert_equal "Simple sentence for empty_cat_#{suffix}.", Word.find_by!(word: "empty_cat_#{suffix}").example_sentence
    assert_equal "Simple sentence for empty_dog_#{suffix}.", Word.find_by!(word: "empty_dog_#{suffix}").example_sentence
    assert_equal "Already set.", Word.find_by!(word: "has_sentence_#{suffix}").example_sentence
  end
end
