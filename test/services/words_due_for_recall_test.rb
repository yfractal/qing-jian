require "test_helper"

class WordsDueForRecallTest < ActiveSupport::TestCase
  def setup
    @created_on = Date.new(2026, 4, 1)
    @word = create_word!("cat")
    @distractor_words = [
      create_word!("dog"),
      create_word!("fish"),
      create_word!("bird")
    ]
    @question = create_word_question_for!(@word, @distractor_words)

    set_word_created_on(@word, @created_on)
  end

  test "newly created word is due on its created date" do
    due_words = WordsDueForRecall.call(day: @created_on)

    assert_includes due_words, @word
  end

  test "new word is not due before its created date" do
    due_words = WordsDueForRecall.call(day: @created_on - 1.day)

    assert_not_includes due_words, @word
  end

  test "word with one correct recall is due after two calendar days" do
    create_record!(created_on: @created_on, correct: true)

    due_words = WordsDueForRecall.call(day: @created_on + 2.days)

    assert_includes due_words, @word
  end

  test "word with one correct recall is not due before two calendar days" do
    create_record!(created_on: @created_on, correct: true)

    due_words = WordsDueForRecall.call(day: @created_on + 1.day)

    assert_not_includes due_words, @word
  end

  test "incorrect recalls do not advance or postpone the schedule" do
    create_record!(created_on: @created_on, correct: true)
    create_record!(created_on: @created_on + 2.days, correct: false)

    due_words = WordsDueForRecall.call(day: @created_on + 3.days)

    assert_includes due_words, @word
  end

  test "overdue word keeps appearing until a later correct recall exists" do
    create_record!(created_on: @created_on, correct: true)
    create_record!(created_on: @created_on + 2.days, correct: false)

    assert_includes WordsDueForRecall.call(day: @created_on + 4.days), @word

    create_record!(created_on: @created_on + 4.days, correct: true)

    assert_not_includes WordsDueForRecall.call(day: @created_on + 5.days), @word
    assert_includes WordsDueForRecall.call(day: @created_on + 7.days), @word
  end

  test "word stops appearing after sixth correct recall" do
    6.times do |index|
      create_record!(created_on: @created_on + index.days, correct: true)
    end

    due_words = WordsDueForRecall.call(day: @created_on + 100.days)

    assert_not_includes due_words, @word
  end

  test "due helper returns true when interval has elapsed" do
    last_correct_record = create_record!(created_on: @created_on, correct: true)

    assert WordsDueForRecall.due?(
      word: @word,
      last_correct_record: last_correct_record,
      remember_times: 1,
      day: @created_on + 2.days
    )
  end

  test "due helper returns false when interval has not elapsed" do
    last_correct_record = create_record!(created_on: @created_on, correct: true)

    assert_not WordsDueForRecall.due?(
      word: @word,
      last_correct_record: last_correct_record,
      remember_times: 1,
      day: @created_on + 1.day
    )
  end

  test "due helper returns false after schedule is complete" do
    last_correct_record = create_record!(created_on: @created_on, correct: true)

    assert_not WordsDueForRecall.due?(
      word: @word,
      last_correct_record: last_correct_record,
      remember_times: 6,
      day: @created_on + 100.days
    )
  end

  private

  def set_word_created_on(word, date)
    word.update!(
      created_at: time_on(date, hour: 9),
      updated_at: time_on(date, hour: 9)
    )
  end

  def create_record!(created_on:, correct:)
    WordQuestionRecord.create!(
      word_question: @question,
      picked_word: correct ? @word : @distractor_words.first,
      is_correct: correct,
      created_at: time_on(created_on, hour: 10),
      updated_at: time_on(created_on, hour: 10)
    )
  end

  def create_word_question_for!(word, distractor_words)
    question = WordQuestion.new(word: word)
    distractor_words.each do |similar_word|
      question.similar_words.build(word: similar_word)
    end
    question.save!
    question
  end

  def create_word!(base_english)
    token = "#{base_english}-#{SecureRandom.hex(4)}"
    Word.create!(
      chinese_meaning: "zh-#{token}",
      english_meaning: token
    )
  end

  def time_on(date, hour:)
    Time.zone.local(date.year, date.month, date.day, hour)
  end
end
