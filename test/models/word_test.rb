require "test_helper"

class WordTest < ActiveSupport::TestCase
  test "valid with word, chinese and english meaning" do
    word = Word.new(word: "zebra", chinese_meaning: "斑马", english_meaning: "An African equid with distinctive stripes.")
    assert word.valid?
  end

  test "invalid without word" do
    word = Word.new(chinese_meaning: "猫", english_meaning: "cat")
    assert_not word.valid?
    assert_includes word.errors[:word], "can't be blank"
  end

  test "invalid without chinese_meaning" do
    word = Word.new(word: "cat", english_meaning: "cat")
    assert_not word.valid?
    assert_includes word.errors[:chinese_meaning], "can't be blank"
  end

  test "invalid without english_meaning" do
    word = Word.new(word: "cat", chinese_meaning: "猫")
    assert_not word.valid?
    assert_includes word.errors[:english_meaning], "can't be blank"
  end

  test "invalid with duplicate word case insensitive" do
    word = Word.new(word: "CAT", chinese_meaning: "猫", english_meaning: "Another gloss")
    assert_not word.valid?
    assert_includes word.errors[:word], "has already been taken"
  end
end
