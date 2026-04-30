require "test_helper"

class WordsDueForRecallTest < ActiveSupport::TestCase
  def setup
    @created_on = Date.new(2026, 4, 1)
    @word = create_word!("cat", created_on: @created_on)
    @distractor_words = [
      create_word!("dog", created_on: @created_on),
      create_word!("fish", created_on: @created_on),
      create_word!("bird", created_on: @created_on)
    ]
    @question = create_word_question_for!(@word, @distractor_words)
  end

  test "returns words with due day on the requested day" do
    due_words = WordsDueForRecall.call(day: @created_on)

    assert_includes due_words, @word
  end

  test "returns overdue words" do
    @word.word_recall_state.update!(due_day: @created_on - 1.day)

    due_words = WordsDueForRecall.call(day: @created_on)

    assert_includes due_words, @word
  end

  test "does not return words due after the requested day" do
    @word.word_recall_state.update!(due_day: @created_on + 1.day)

    due_words = WordsDueForRecall.call(day: @created_on)

    assert_not_includes due_words, @word
  end

  test "does not return completed words with nil due day" do
    @word.word_recall_state.update!(due_day: nil)

    due_words = WordsDueForRecall.call(day: @created_on + 100.days)

    assert_not_includes due_words, @word
  end

  test "excludes words by ids" do
    other_due_word = create_word!("horse", created_on: @created_on)

    due_words = WordsDueForRecall.call(
      day: @created_on,
      excluding_word_ids: [ @word.id.to_s ]
    )

    assert_not_includes due_words, @word
    assert_includes due_words, other_due_word
  end

  test "ignores blank and invalid excluded ids" do
    due_words = WordsDueForRecall.call(
      day: @created_on,
      excluding_word_ids: [ "", "abc", nil, @word.id.to_s ]
    )

    assert_not_includes due_words, @word
  end

  test "correct recall increments remember times and sets next due day" do
    create_record!(created_on: @created_on, correct: true)

    @word.word_recall_state.reload

    assert_equal 1, @word.word_recall_state.remember_times
    assert_equal @created_on + 2.days, @word.word_recall_state.due_day
  end

  test "incorrect recall does not change recall state" do
    original_state = @word.word_recall_state.attributes.slice("remember_times", "due_day")

    create_record!(created_on: @created_on, correct: false)

    @word.word_recall_state.reload

    assert_equal original_state, @word.word_recall_state.attributes.slice("remember_times", "due_day")
  end

  test "overdue word keeps appearing until a later correct recall updates due day" do
    create_record!(created_on: @created_on, correct: true)
    create_record!(created_on: @created_on + 2.days, correct: false)

    due_words = WordsDueForRecall.call(day: @created_on + 3.days)

    assert_includes due_words, @word

    create_record!(created_on: @created_on + 4.days, correct: true)

    assert_not_includes WordsDueForRecall.call(day: @created_on + 5.days), @word
    assert_includes WordsDueForRecall.call(day: @created_on + 7.days), @word
  end

  test "sixth correct recall completes the word and clears due day" do
    6.times do |index|
      create_record!(created_on: @created_on + index.days, correct: true)
    end

    @word.word_recall_state.reload

    assert_equal 6, @word.word_recall_state.remember_times
    assert_nil @word.word_recall_state.due_day
    assert_not_includes WordsDueForRecall.call(day: @created_on + 100.days), @word
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

  def create_record!(created_on:, correct:)
    WordQuestionRecord.create!(
      word_question: @question,
      picked_choice_token: correct ? "word:#{@word.id}" : "similar_word:#{@question.similar_words.first.id}",
      picked_choice_word: correct ? @word.word : @question.similar_words.first.word,
      is_correct: correct,
      created_at: time_on(created_on, hour: 10),
      updated_at: time_on(created_on, hour: 10)
    )
  end

  def create_word_question_for!(word, distractor_words)
    question = WordQuestion.new(word: word)
    distractor_words.each do |similar_word|
      question.similar_words.build(
        word: similar_word.word,
        english_meaning: similar_word.english_meaning,
        chinese_meaning: similar_word.chinese_meaning
      )
    end
    question.save!
    question
  end

  def create_word!(base_english, created_on:)
    token = "#{base_english}-#{SecureRandom.hex(4)}"
    Word.create!(
      word: token,
      chinese_meaning: "zh-#{token}",
      english_meaning: token,
      created_at: time_on(created_on, hour: 9),
      updated_at: time_on(created_on, hour: 9)
    )
  end

  def time_on(date, hour:)
    Time.zone.local(date.year, date.month, date.day, hour)
  end
end
