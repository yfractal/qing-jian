require "test_helper"

module BookPlugin
  class FlashCardTest < ActiveSupport::TestCase
    test "defaults json fields and requires book_html" do
      book = Book.new(title: "B")
      book.save!(validate: false)

      html = BookHtml.create!(
        book:,
        page_number: 1,
        layout: {
          "width" => 100.0,
          "height" => 200.0,
          "items" => [
            { "type" => "text", "text" => "chunk", "bbox" => [10, 20, 50, 35], "font_size" => 12 }
          ]
        }
      )
      card = FlashCard.new(book:, book_html: html)

      assert card.valid?
      assert_equal({}, card.areas_to_show)
      assert_equal([], card.items_to_remember)
      assert_equal([], card.vector_adjustments)
      assert_equal([], card.text_adjustments)
    end

    test "creates initial recall state" do
      book = Book.new(title: "B")
      book.save!(validate: false)

      html = BookHtml.create!(
        book:,
        page_number: 1,
        layout: {
          "width" => 100.0,
          "height" => 200.0,
          "items" => [
            { "type" => "text", "text" => "chunk", "bbox" => [10, 20, 50, 35], "font_size" => 12 }
          ]
        }
      )
      card = FlashCard.create!(book:, book_html: html)

      assert_equal 0, card.recall_state.remember_times
      assert_equal card.created_at.to_date, card.recall_state.due_day
    end
  end
end
