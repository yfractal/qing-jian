require "test_helper"

module BookPlugin
  class FlashCardRecallRecordTest < ActiveSupport::TestCase
    test "requires flash card and correctness flag" do
      record = FlashCardRecallRecord.new

      assert_not record.valid?
      assert_includes record.errors[:flash_card], "must exist"
      assert_includes record.errors[:is_correct], "is not included in the list"
    end
  end
end
