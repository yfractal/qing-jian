require "test_helper"

class WordSelfRecallRecordTest < ActiveSupport::TestCase
  setup do
    @created_on = Date.new(2026, 4, 1)
    @word = Word.create!(
      word: "flash-test-#{SecureRandom.hex(4)}",
      english_meaning: "test",
      chinese_meaning: "测试",
      created_at: Time.zone.local(@created_on.year, @created_on.month, @created_on.day, 9),
      updated_at: Time.zone.local(@created_on.year, @created_on.month, @created_on.day, 9)
    )
  end

  test "requires is_correct true or false" do
    record = WordSelfRecallRecord.new(word: @word)
    assert_not record.valid?

    record.is_correct = true
    assert record.valid?
  end

  test "correct record advances word recall state" do
    ts = Time.zone.local(@created_on.year, @created_on.month, @created_on.day, 10)
    WordSelfRecallRecord.create!(
      word: @word,
      is_correct: true,
      created_at: ts,
      updated_at: ts
    )

    @word.word_recall_state.reload
    assert_equal 1, @word.word_recall_state.remember_times
    assert_equal @created_on + 2.days, @word.word_recall_state.due_day
  end

  test "incorrect record does not change recall state" do
    before = @word.word_recall_state.attributes.slice("remember_times", "due_day")

    ts = Time.zone.local(@created_on.year, @created_on.month, @created_on.day, 10)
    WordSelfRecallRecord.create!(
      word: @word,
      is_correct: false,
      created_at: ts,
      updated_at: ts
    )

    @word.word_recall_state.reload
    assert_equal before, @word.word_recall_state.attributes.slice("remember_times", "due_day")
  end
end
