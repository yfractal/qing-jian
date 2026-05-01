require "test_helper"

class RememberWordsStatisticsTest < ActiveSupport::TestCase
  include ActiveSupport::Testing::TimeHelpers

  def setup
    WordQuestionRecord.delete_all
    SimilarWord.delete_all
    WordQuestion.delete_all
    WordRecallState.delete_all
    Word.delete_all
  end

  test "returns total words, remembered words, and completion rate" do
    remembered = create_word!("remembered")
    pending = create_word!("pending")

    remembered.word_recall_state.update!(remember_times: 6)
    pending.word_recall_state.update!(remember_times: 3)

    stats = RememberWordsStatistics.call(day: Date.current, days: 7)

    assert_equal 2, stats[:total_words]
    assert_equal 1, stats[:remembered_words]
    assert_equal 50, stats[:completion_rate_percent]
    assert_equal stats[:daily_review_counts][Date.current].to_i, stats[:reviews_today]
  end

  test "builds daily review heatmap counts and max count" do
    word = create_word!("daily")
    question = create_question_for!(word)

    2.times { create_record!(question, created_at: Time.zone.local(2026, 4, 1, 10), is_correct: true) }
    create_record!(question, created_at: Time.zone.local(2026, 4, 2, 10), is_correct: false)

    stats = RememberWordsStatistics.call(day: Date.new(2026, 4, 2), days: 7)

    assert_equal 2, stats[:daily_review_counts][Date.new(2026, 4, 1)]
    assert_equal 1, stats[:daily_review_counts][Date.new(2026, 4, 2)]
    assert_equal 2, stats[:heatmap_max_count]
  end

  test "returns useful trailing metrics" do
    word = create_word!("trailing")
    question = create_question_for!(word)

    create_record!(question, created_at: Time.zone.local(2026, 4, 2, 9), is_correct: true)
    create_record!(question, created_at: Time.zone.local(2026, 4, 3, 9), is_correct: false)

    stats = RememberWordsStatistics.call(day: Date.new(2026, 4, 3), days: 30)

    assert_equal 2, stats[:reviews_last_7_days]
    assert_equal 2, stats[:active_days_last_30_days]
  end

  test "default heatmap spans full grid and ends on requested day" do
    stats = RememberWordsStatistics.call(day: Date.new(2026, 6, 15))

    assert_equal RememberWordsStatistics::HEATMAP_GRID_DAYS, stats[:daily_review_counts].size
    assert_equal Date.new(2025, 6, 10), stats[:daily_review_counts].keys.min
    assert_equal Date.new(2026, 6, 15), stats[:daily_review_counts].keys.max
    assert_equal stats[:daily_review_counts][Date.new(2026, 6, 15)].to_i, stats[:reviews_today]
  end

  test "maps counts into heat levels" do
    assert_equal 0, RememberWordsStatistics.heat_level(count: 0, max_count: 5)
    assert_equal 1, RememberWordsStatistics.heat_level(count: 1, max_count: 8)
    assert_equal 4, RememberWordsStatistics.heat_level(count: 8, max_count: 8)
  end

  private

  def create_word!(token)
    Word.create!(
      word: "#{token}_#{SecureRandom.hex(4)}",
      english_meaning: token,
      chinese_meaning: "zh_#{token}"
    )
  end

  def create_question_for!(word)
    question = WordQuestion.new(word: word)
    3.times do |index|
      question.similar_words.build(
        word: "#{word.word}_similar_#{index}_#{SecureRandom.hex(2)}",
        english_meaning: "sim#{index}",
        chinese_meaning: "similar_#{index}"
      )
    end
    question.save!
    question
  end

  def create_record!(question, created_at: Time.zone.now, is_correct: true)
    WordQuestionRecord.create!(
      word_question: question,
      picked_choice_token: is_correct ? "word:#{question.word_id}" : "similar_word:#{question.similar_words.first.id}",
      picked_choice_word: is_correct ? question.word.word : question.similar_words.first.word,
      is_correct: is_correct,
      created_at: created_at,
      updated_at: created_at
    )
  end
end
