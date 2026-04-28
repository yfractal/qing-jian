require "test_helper"

class WordTest < ActiveSupport::TestCase
  test "valid with chinese and english meaning" do
    word = Word.new(chinese_meaning: "猫", english_meaning: "cat")
    assert word.valid?
  end

  test "invalid without chinese_meaning" do
    word = Word.new(english_meaning: "cat")
    assert_not word.valid?
    assert_includes word.errors[:chinese_meaning], "can't be blank"
  end

  test "invalid without english_meaning" do
    word = Word.new(chinese_meaning: "猫")
    assert_not word.valid?
    assert_includes word.errors[:english_meaning], "can't be blank"
  end
end
