# frozen_string_literal: true

require "test_helper"

class WordQuestionRecordsControllerTest < ActionDispatch::IntegrationTest
  def setup
    @word = Word.create!(
      word: "test_word_#{SecureRandom.hex(4)}",
      english_meaning: "test",
      chinese_meaning: "测试"
    )
    @question = WordQuestion.new(word: @word)
    @question.similar_words.build(word: "similar_1_#{SecureRandom.hex(4)}", english_meaning: "s1", chinese_meaning: "s1")
    @question.similar_words.build(word: "similar_2_#{SecureRandom.hex(4)}", english_meaning: "s2", chinese_meaning: "s2")
    @question.similar_words.build(word: "similar_3_#{SecureRandom.hex(4)}", english_meaning: "s3", chinese_meaning: "s3")
    @question.save!
  end

  test "creates a correct record and redirects to root with result record id" do
    assert_difference("WordQuestionRecord.count", 1) do
      post word_question_records_url, params: {
        word_question_record: {
          word_question_id: @question.id,
          picked_choice: "word:#{@word.id}"
        }
      }
    end

    record = WordQuestionRecord.order(:created_at).last
    assert_equal true, record.is_correct
    assert_redirected_to root_url(direction: "english_to_chinese", result_record_id: record.id)
  end

  test "creates an incorrect record and redirects to root with result record id" do
    wrong_choice = @question.similar_words.first

    assert_difference("WordQuestionRecord.count", 1) do
      post word_question_records_url, params: {
        word_question_record: {
          word_question_id: @question.id,
          picked_choice: "similar_word:#{wrong_choice.id}"
        }
      }
    end

    record = WordQuestionRecord.order(:created_at).last
    assert_equal false, record.is_correct
    assert_redirected_to root_url(direction: "english_to_chinese", result_record_id: record.id)
  end

  test "preserves existing recalled word ids on successful redirect" do
    previous_word = Word.create!(
      word: "previous_#{SecureRandom.hex(4)}",
      english_meaning: "previous",
      chinese_meaning: "previous"
    )

    post word_question_records_url, params: {
      recalled_word_ids: previous_word.id.to_s,
      word_question_record: {
        word_question_id: @question.id,
        picked_choice: "word:#{@word.id}"
      }
    }

    record = WordQuestionRecord.order(:created_at).last
    assert_redirected_to root_url(
      direction: "english_to_chinese",
      recalled_word_ids: previous_word.id.to_s,
      result_record_id: record.id
    )
  end

  test "preserves recalled word ids without appending answered word id" do
    post word_question_records_url, params: {
      recalled_word_ids: @word.id.to_s,
      word_question_record: {
        word_question_id: @question.id,
        picked_choice: "word:#{@word.id}"
      }
    }

    record = WordQuestionRecord.order(:created_at).last
    assert_redirected_to root_url(
      direction: "english_to_chinese",
      recalled_word_ids: @word.id.to_s,
      result_record_id: record.id
    )
  end

  test "preserves existing recalled word ids when record creation fails" do
    previous_word = Word.create!(
      word: "previous_failure_#{SecureRandom.hex(4)}",
      english_meaning: "previous failure",
      chinese_meaning: "previous failure"
    )

    assert_no_difference("WordQuestionRecord.count") do
      post word_question_records_url, params: {
        recalled_word_ids: previous_word.id.to_s,
        word_question_record: {
          word_question_id: "missing",
          picked_choice: "word:#{@word.id}"
        }
      }
    end

    assert_redirected_to root_url(direction: "english_to_chinese", recalled_word_ids: previous_word.id.to_s)
    assert_equal "Could not save answer.", flash[:alert]
  end

  test "preserves english_to_chinese direction on successful redirect" do
    post word_question_records_url, params: {
      direction: "english_to_chinese",
      word_question_record: {
        word_question_id: @question.id,
        picked_choice: "word:#{@word.id}"
      }
    }

    record = WordQuestionRecord.order(:created_at).last
    assert_redirected_to root_url(direction: "english_to_chinese", result_record_id: record.id)
  end

  test "preserves chinese_to_english direction on failure redirect" do
    post word_question_records_url, params: {
      direction: "chinese_to_english",
      word_question_record: {
        word_question_id: "missing",
        picked_choice: "word:#{@word.id}"
      }
    }

    assert_redirected_to root_url(direction: "chinese_to_english")
    assert_equal "Could not save answer.", flash[:alert]
  end
end
