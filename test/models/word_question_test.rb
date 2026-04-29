require "test_helper"

class WordQuestionTest < ActiveSupport::TestCase
  def build_question_with_similar_count(count)
    question = WordQuestion.new(word: words(:cat))
    similar_words = [words(:dog), words(:fish), words(:bird)].first(count)
    similar_words.each do |word|
      question.similar_words.build(word: word)
    end
    question
  end

  test "valid with a word and exactly 3 similar words" do
    question = build_question_with_similar_count(3)
    assert question.valid?
  end

  test "invalid without a word" do
    question = WordQuestion.new
    question.similar_words.build(word: words(:dog))
    question.similar_words.build(word: words(:fish))
    question.similar_words.build(word: words(:bird))
    assert_not question.valid?
    assert_includes question.errors[:word], "must exist"
  end

  test "invalid with fewer than 3 similar words" do
    question = build_question_with_similar_count(2)
    assert_not question.valid?
    assert_includes question.errors[:similar_words], "must have exactly 3"
  end

  test "invalid with more than 3 similar words" do
    question = build_question_with_similar_count(3)
    question.similar_words.build(word: words(:cat))
    assert_not question.valid?
    assert_includes question.errors[:similar_words], "must have exactly 3"
  end
end
