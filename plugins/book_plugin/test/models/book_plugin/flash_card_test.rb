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
    end
  end
end
