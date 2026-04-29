# frozen_string_literal: true

require "test_helper"

class WordQuestionRecordsControllerTest < ActionDispatch::IntegrationTest
  def setup
    @word = Word.create!(
      word: "test_word_#{Time.now.to_i}",
      english_meaning: "test",
      chinese_meaning: "测试"
    )
    @question = WordQuestion.new(word: @word)
    @question.similar_words.build(word: Word.create!(word: "similar_1_#{Time.now.to_i}", english_meaning: "s1", chinese_meaning: "s1"))
    @question.similar_words.build(word: Word.create!(word: "similar_2_#{Time.now.to_i}", english_meaning: "s2", chinese_meaning: "s2"))
    @question.similar_words.build(word: Word.create!(word: "similar_3_#{Time.now.to_i}", english_meaning: "s3", chinese_meaning: "s3"))
    @question.save!
  end

  test "creates a correct record and redirects to root" do
    assert_difference("WordQuestionRecord.count", 1) do
      post word_question_records_url, params: {
        word_question_record: {
          word_question_id: @question.id,
          picked_word_id: @word.id
        }
      }
    end

    record = WordQuestionRecord.order(:created_at).last
    assert_equal true, record.is_correct
    assert_redirected_to root_url
  end

  test "creates an incorrect record and redirects to root" do
    wrong_word = @question.similar_words.first.word

    assert_difference("WordQuestionRecord.count", 1) do
      post word_question_records_url, params: {
        word_question_record: {
          word_question_id: @question.id,
          picked_word_id: wrong_word.id
        }
      }
    end

    record = WordQuestionRecord.order(:created_at).last
    assert_equal false, record.is_correct
    assert_redirected_to root_url
  end
end
