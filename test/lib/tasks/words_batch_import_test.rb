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
      OpenRouterWordMeaningClient::BatchMeaningResult.new(
        word: "cat",
        english_meaning: "A small carnivorous mammal",
        chinese_meaning: "猫"
      ),
      OpenRouterWordMeaningClient::BatchMeaningResult.new(
        word: "dog",
        english_meaning: "A domesticated carnivorous mammal",
        chinese_meaning: "狗"
      )
    ]
    mock_client = Minitest::Mock.new
    mock_client.expect(:batch_lookup, mock_results, [%w[cat dog]])

    OpenRouterWordMeaningClient.stub(:new, mock_client) do
      assert_difference("Word.count", 2) do
        @task.invoke("cat,dog")
      end
    end

    mock_client.verify
  end

  test "imports words from file input" do
    file_path = Rails.root.join("tmp", "batch_words_test.txt")
    File.write(file_path, "apple\nbanana\napple\n")

    mock_results = [
      OpenRouterWordMeaningClient::BatchMeaningResult.new(word: "apple", english_meaning: "A fruit", chinese_meaning: "苹果"),
      OpenRouterWordMeaningClient::BatchMeaningResult.new(word: "banana", english_meaning: "Another fruit", chinese_meaning: "香蕉")
    ]
    mock_client = Minitest::Mock.new
    mock_client.expect(:batch_lookup, mock_results, [%w[apple banana]])

    OpenRouterWordMeaningClient.stub(:new, mock_client) do
      assert_difference("Word.count", 2) do
        @task.invoke("file:#{file_path}")
      end
    end

    mock_client.verify
  ensure
    File.delete(file_path) if file_path && File.exist?(file_path)
  end
end
