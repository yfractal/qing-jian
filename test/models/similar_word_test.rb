require "test_helper"

class SimilarWordTest < ActiveSupport::TestCase
  test "valid with word question and word-shaped fields" do
    similar_word = SimilarWord.new(
      word_question: word_questions(:cat_question),
      word: "kitten",
      english_meaning: "A young cat.",
      chinese_meaning: "小猫"
    )
    assert similar_word.valid?
  end

  test "invalid without word_question" do
    similar_word = SimilarWord.new(
      word: "kitten",
      english_meaning: "A young cat.",
      chinese_meaning: "小猫"
    )
    assert_not similar_word.valid?
    assert_includes similar_word.errors[:word_question], "must exist"
  end

  test "invalid without word" do
    similar_word = SimilarWord.new(
      word_question: word_questions(:cat_question),
      english_meaning: "A young cat.",
      chinese_meaning: "小猫"
    )
    assert_not similar_word.valid?
    assert_includes similar_word.errors[:word], "can't be blank"
  end

  test "invalid without english meaning" do
    similar_word = SimilarWord.new(
      word_question: word_questions(:cat_question),
      word: "kitten",
      chinese_meaning: "小猫"
    )
    assert_not similar_word.valid?
    assert_includes similar_word.errors[:english_meaning], "can't be blank"
  end

  test "invalid without chinese meaning" do
    similar_word = SimilarWord.new(
      word_question: word_questions(:cat_question),
      word: "kitten",
      english_meaning: "A young cat."
    )
    assert_not similar_word.valid?
    assert_includes similar_word.errors[:chinese_meaning], "can't be blank"
  end
end
