require "test_helper"

class WordFlashRememberControllerTest < ActionDispatch::IntegrationTest
  setup do
    @day = Date.new(2026, 5, 3)
    travel_to Time.zone.local(@day.year, @day.month, @day.day, 10, 0, 0) do
      @due = Word.create!(word: "due-#{SecureRandom.hex(3)}", english_meaning: "a", chinese_meaning: "甲")
      @due.word_recall_state.update!(due_day: @day)
      @other = Word.create!(word: "other-#{SecureRandom.hex(3)}", english_meaning: "b", chinese_meaning: "乙")
      @other.word_recall_state.update!(due_day: @day)
    end
  end

  test "index shows one due word and self-report form" do
    travel_to Time.zone.local(@day.year, @day.month, @day.day, 10, 0, 0) do
      get word_flash_remember_path

      assert_response :success
      assert_select "h1", /Word flash/i
      assert_select "form[action=?]", word_self_recall_records_path do
        assert_select "input[name='word_self_recall_record[word_id]']", count: 1
        assert_select "button[name='word_self_recall_record[is_correct]'][value='true']"
        assert_select "button[name='word_self_recall_record[is_correct]'][value='false']"
      end
    end
  end

  test "index skips reviewed words in pass" do
    travel_to Time.zone.local(@day.year, @day.month, @day.day, 10, 0, 0) do
      get word_flash_remember_path, params: { reviewed_word_ids: @due.id.to_s }

      assert_response :success
      assert_select "input[name='word_self_recall_record[word_id]'][value='#{@other.id}']", visible: false
    end
  end

  test "index restarts pass when reviewed ids exhaust due words" do
    travel_to Time.zone.local(@day.year, @day.month, @day.day, 10, 0, 0) do
      get word_flash_remember_path, params: { reviewed_word_ids: [ @due.id, @other.id ].join(",") }

      assert_redirected_to word_flash_remember_path
      assert_match(/another.*pass/i, flash[:notice])
    end
  end
end
