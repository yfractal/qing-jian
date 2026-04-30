require "test_helper"

class TodayWordsProgressTest < ActiveSupport::TestCase
  test "today words include due words and remembered-today words" do
    due_word = create_word!("due_word")
    remembered_word = create_word!("remembered_word")

    due_word.word_recall_state.update!(due_day: Date.current)
    remembered_word.word_recall_state.update!(due_day: Date.current + 5.days)

    question = create_question_for!(remembered_word)
    WordQuestionRecord.create!(
      word_question: question,
      picked_choice_token: "word:#{remembered_word.id}",
      picked_choice_word: remembered_word.word,
      is_correct: true,
      created_at: Time.zone.now
    )

    result = TodayWordsProgress.call(day: Date.current)
    result_ids = result.map { |item| item[:word].id }

    assert_includes result_ids, due_word.id
    assert_includes result_ids, remembered_word.id
  end

  test "marks reviewed when word has a correct record today" do
    reviewed_word = create_word!("reviewed")
    pending_word = create_word!("pending")
    reviewed_word.word_recall_state.update!(due_day: Date.current)
    pending_word.word_recall_state.update!(due_day: Date.current)

    reviewed_question = create_question_for!(reviewed_word)
    WordQuestionRecord.create!(
      word_question: reviewed_question,
      picked_choice_token: "word:#{reviewed_word.id}",
      picked_choice_word: reviewed_word.word,
      is_correct: true,
      created_at: Time.zone.now
    )

    result = TodayWordsProgress.call(day: Date.current)
    reviewed_item = result.find { |item| item[:word].id == reviewed_word.id }
    pending_item = result.find { |item| item[:word].id == pending_word.id }

    assert_equal true, reviewed_item[:reviewed]
    assert_equal false, pending_item[:reviewed]
  end

  private

  def create_word!(base_english)
    token = "#{base_english}-#{SecureRandom.hex(4)}"
    Word.create!(
      word: token,
      chinese_meaning: "zh-#{token}",
      english_meaning: token
    )
  end

  def create_question_for!(word)
    question = WordQuestion.new(word: word)
    3.times do |index|
      question.similar_words.build(
        word: "#{word.word}-similar-#{index}-#{SecureRandom.hex(2)}",
        english_meaning: "similar-meaning-#{index}",
        chinese_meaning: "相似含义#{index}"
      )
    end
    question.save!
    question
  end
end
