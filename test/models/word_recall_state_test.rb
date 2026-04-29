require "test_helper"

class WordRecallStateTest < ActiveSupport::TestCase
  test "valid with word, remember times, and due day" do
    state = WordRecallState.new(
      word: words(:cat),
      remember_times: 0,
      due_day: Date.current
    )

    assert state.valid?
  end

  test "invalid without word" do
    state = WordRecallState.new(remember_times: 0, due_day: Date.current)

    assert_not state.valid?
    assert_includes state.errors[:word], "must exist"
  end
end
