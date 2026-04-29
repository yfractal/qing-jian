require "test_helper"

class SimilarWordTest < ActiveSupport::TestCase
  test "valid when owned by a Word and pointing to another Word" do
    owner = words(:cat)
    similar = words(:dog)
    sw = SimilarWord.new(similar_wordable: owner, word: similar)
    assert sw.valid?
  end

  test "invalid without similar_wordable" do
    sw = SimilarWord.new(word: words(:dog))
    assert_not sw.valid?
    assert_includes sw.errors[:similar_wordable], "must exist"
  end

  test "invalid without word" do
    sw = SimilarWord.new(similar_wordable: words(:cat))
    assert_not sw.valid?
    assert_includes sw.errors[:word], "must exist"
  end
end
