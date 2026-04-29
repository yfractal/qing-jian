require "test_helper"

class WordQuestionRecordTest < ActiveSupport::TestCase
  def setup
    @question = word_questions(:cat_question)
  end

  test "valid with a question and a picked word" do
    record = WordQuestionRecord.new(
      word_question: @question,
      picked_word: words(:cat),
      is_correct: true
    )
    assert record.valid?
  end

  test "invalid without word_question" do
    record = WordQuestionRecord.new(picked_word: words(:cat), is_correct: false)
    assert_not record.valid?
    assert_includes record.errors[:word_question], "must exist"
  end

  test "invalid without picked_word" do
    record = WordQuestionRecord.new(word_question: @question, is_correct: false)
    assert_not record.valid?
    assert_includes record.errors[:picked_word], "must exist"
  end

  test "is_correct defaults to false" do
    record = WordQuestionRecord.new
    assert_equal false, record.is_correct
  end

  test "correct? returns true when is_correct is true" do
    record = WordQuestionRecord.new(is_correct: true)
    assert record.correct?
  end

  test "correct? returns false when is_correct is false" do
    record = WordQuestionRecord.new(is_correct: false)
    assert_not record.correct?
  end
end
