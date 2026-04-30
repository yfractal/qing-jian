require "test_helper"

class WordTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    clear_enqueued_jobs
  end

  teardown do
    clear_enqueued_jobs
  end

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

  test "valid without pronunciation" do
    word = Word.new(word: "harbor", chinese_meaning: "港口", english_meaning: "a place for ships")
    assert word.valid?
  end

  test "valid with pronunciation" do
    word = Word.new(
      word: "resilient",
      chinese_meaning: "有韧性的",
      english_meaning: "able to recover quickly",
      pronunciation: "/rɪˈzɪliənt/"
    )
    assert word.valid?
  end

  test "invalid when pronunciation is too long" do
    word = Word.new(
      word: "overflow",
      chinese_meaning: "溢出",
      english_meaning: "to spill over",
      pronunciation: "a" * 256
    )

    assert_not word.valid?
    assert_includes word.errors[:pronunciation], "is too long (maximum is 255 characters)"
  end

  test "enqueue single question job on create by default" do
    assert_enqueued_with(job: CreateWordQuestionJob) do
      Word.create!(word: "callback_enqueue_word", chinese_meaning: "中文", english_meaning: "gloss")
    end
  end

  test "does not enqueue single question job when callback is skipped" do
    assert_no_enqueued_jobs(only: CreateWordQuestionJob) do
      Word.create!(
        word: "callback_skip_word",
        chinese_meaning: "中文",
        english_meaning: "gloss",
        skip_create_word_question_job: true
      )
    end
  end
end
