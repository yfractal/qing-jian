require "test_helper"

class WordSelfRecallRecordsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @day = Date.new(2026, 5, 3)
    travel_to Time.zone.local(@day.year, @day.month, @day.day, 12, 0, 0) do
      @word = Word.create!(
        word: "self-report-#{SecureRandom.hex(4)}",
        english_meaning: "hello",
        chinese_meaning: "你好"
      )
      @word.word_recall_state.update!(due_day: @day)
    end
  end

  test "create redirects to word show with reviewed_word_ids and flash_remember" do
    travel_to Time.zone.local(@day.year, @day.month, @day.day, 12, 0, 0) do
      assert_difference -> { WordSelfRecallRecord.count }, +1 do
        post word_self_recall_records_path,
             params: {
               reviewed_word_ids: "999",
               word_self_recall_record: { word_id: @word.id, is_correct: "true" }
             }
      end

      assert_redirected_to word_path(
        @word,
        reviewed_word_ids: "999,#{@word.id}",
        flash_remember: "1"
      )
    end
  end

  test "create rejects invalid word id" do
    travel_to Time.zone.local(@day.year, @day.month, @day.day, 12, 0, 0) do
      assert_no_difference -> { WordSelfRecallRecord.count } do
        post word_self_recall_records_path,
             params: {
               word_self_recall_record: { word_id: 0, is_correct: "true" }
             }
      end

      assert_redirected_to word_flash_remember_path
      assert_match(/could not save/i, flash[:alert])
    end
  end
end
