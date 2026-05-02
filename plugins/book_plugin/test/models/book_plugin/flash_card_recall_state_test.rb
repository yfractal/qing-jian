require "test_helper"

module BookPlugin
  class FlashCardRecallStateTest < ActiveSupport::TestCase
    test "requires a flash card and defaults remember fields" do
      state = FlashCardRecallState.new

      assert_not state.valid?
      assert_includes state.errors[:flash_card], "must exist"
      assert_equal 0, FlashCardRecallState.new.remember_times
    end
  end
end
