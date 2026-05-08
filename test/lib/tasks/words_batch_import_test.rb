# frozen_string_literal: true

require "test_helper"
require "rake"

class WordsBatchImportTaskTest < ActiveSupport::TestCase
  setup do
    Rails.application.load_tasks if Rake::Task.tasks.empty?
    @task = Rake::Task["words:batch_import"]
    @task.reenable
  end

  test "imports words from comma separated input" do
    mock_results = [
      Llm::OpenRouterWordMeaningClient::BatchMeaningResult.new(
        word: "yak",
        english_meaning: "A long-haired wild ox",
        chinese_meaning: "牦牛",
        pronunciation: "/jæk/",
        example_sentence: "The yak grazed slowly."
      ),
      Llm::OpenRouterWordMeaningClient::BatchMeaningResult.new(
        word: "ibex",
        english_meaning: "A wild mountain goat",
        chinese_meaning: "北山羊",
        pronunciation: "/ˈaɪbɛks/",
        example_sentence: "The ibex climbed the cliffs."
      )
    ]
    fake_client = Class.new do
      attr_reader :received_words

      def initialize(results)
        @results = results
      end

      def batch_lookup(words)
        @received_words = words
        @results
      end
    end.new(mock_results)

    original_new = Llm::OpenRouterWordMeaningClient.method(:new)
    Llm::OpenRouterWordMeaningClient.define_singleton_method(:new) { |*_args, **_kwargs| fake_client }
    begin
      assert_difference("Word.count", 2) do
        @task.invoke("yak,ibex")
      end
    ensure
      Llm::OpenRouterWordMeaningClient.singleton_class.send(:define_method, :new, original_new)
    end

    assert_equal %w[yak ibex], fake_client.received_words

    assert_equal "The yak grazed slowly.", Word.find_by!(word: "yak").example_sentence
  end

  test "imports words from file input" do
    file_path = Rails.root.join("tmp", "batch_words_test.txt")
    File.write(file_path, "apple\nbanana\napple\n")

    mock_results = [
      Llm::OpenRouterWordMeaningClient::BatchMeaningResult.new(
        word: "apple",
        english_meaning: "A fruit",
        chinese_meaning: "苹果",
        pronunciation: "/ˈæpəl/",
        example_sentence: "I ate an apple."
      ),
      Llm::OpenRouterWordMeaningClient::BatchMeaningResult.new(
        word: "banana",
        english_meaning: "Another fruit",
        chinese_meaning: "香蕉",
        pronunciation: "/bəˈnænə/",
        example_sentence: "She peeled a banana."
      )
    ]
    fake_client = Class.new do
      attr_reader :received_words

      def initialize(results)
        @results = results
      end

      def batch_lookup(words)
        @received_words = words
        @results
      end
    end.new(mock_results)

    original_new = Llm::OpenRouterWordMeaningClient.method(:new)
    Llm::OpenRouterWordMeaningClient.define_singleton_method(:new) { |*_args, **_kwargs| fake_client }
    begin
      assert_difference("Word.count", 2) do
        @task.invoke("file:#{file_path}")
      end
    ensure
      Llm::OpenRouterWordMeaningClient.singleton_class.send(:define_method, :new, original_new)
    end

    assert_equal %w[apple banana], fake_client.received_words

    assert_equal "I ate an apple.", Word.find_by!(word: "apple").example_sentence
  ensure
    File.delete(file_path) if file_path && File.exist?(file_path)
  end
end
