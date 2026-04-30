require "test_helper"

class WordQuestionTest < ActiveSupport::TestCase
  def build_question_with_similar_count(count)
    question = WordQuestion.new(word: words(:cat))
    [
      [ "dog", "A domesticated carnivorous mammal.", "狗" ],
      [ "fish", "A limbless cold-blooded vertebrate animal.", "鱼" ],
      [ "bird", "A warm-blooded egg-laying vertebrate animal.", "鸟" ]
    ].first(count).each do |word, english_meaning, chinese_meaning|
      question.similar_words.build(
        word: word,
        english_meaning: english_meaning,
        chinese_meaning: chinese_meaning
      )
    end
    question
  end

  test "valid with a word and exactly 3 similar words" do
    question = build_question_with_similar_count(3)
    assert question.valid?
  end

  test "invalid without a word" do
    question = WordQuestion.new
    question.similar_words.build(word: "dog", english_meaning: "A dog.", chinese_meaning: "狗")
    question.similar_words.build(word: "fish", english_meaning: "A fish.", chinese_meaning: "鱼")
    question.similar_words.build(word: "bird", english_meaning: "A bird.", chinese_meaning: "鸟")
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
    question.similar_words.build(word: "kitten", english_meaning: "A young cat.", chinese_meaning: "小猫")
    assert_not question.valid?
    assert_includes question.errors[:similar_words], "must have exactly 3"
  end

  test "choices expose tokens and correctness for target and similar words" do
    question = word_questions(:cat_question)

    choices = question.choices
    assert_equal 4, choices.size
    assert_equal "word:#{question.word.id}", choices.first.token
    assert_equal question.word.word, choices.first.word
    assert_equal true, choices.first.correct
    assert_equal "similar_word:#{similar_words(:dog_choice_for_cat_question).id}", choices.second.token
    assert_equal false, choices.second.correct
  end
end
