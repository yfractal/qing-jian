require "test_helper"

module BookPlugin
  class FlashCardRecallRecordsControllerTest < ActionDispatch::IntegrationTest
    test "create saves remembered result and redirects with result state" do
      book = create_book
      card = create_flash_card(book:)

      assert_difference("FlashCardRecallRecord.count", 1) do
        post "/books/books/#{book.id}/flash_card_recall_records", params: {
          flash_card_recall_record: {
            flash_card_id: card.id,
            is_correct: "true"
          },
          reviewed_flash_card_ids: "12"
        }
      end

      record = FlashCardRecallRecord.last
      assert record.correct?
      assert_redirected_to "/books/books/#{book.id}/flash_cards/remember?result_record_id=#{record.id}&reviewed_flash_card_ids=12"
    end

    test "create saves review-again result without incrementing recall state" do
      book = create_book
      card = create_flash_card(book:)

      post "/books/books/#{book.id}/flash_card_recall_records", params: {
        flash_card_recall_record: {
          flash_card_id: card.id,
          is_correct: "false"
        }
      }

      record = FlashCardRecallRecord.last
      assert_not record.correct?
      assert_equal 0, card.recall_state.reload.remember_times
    end

    private

    def create_book
      book = Book.new(title: "Book")
      book.save!(validate: false)
      book
    end

    def create_flash_card(book:)
      html = BookHtml.create!(
        book:,
        page_number: 1,
        layout: {
          "width" => 100.0,
          "height" => 200.0,
          "items" => [
            { "type" => "text", "text" => "Alpha", "bbox" => [10, 20, 50, 35], "font_size" => 12 }
          ]
        }
      )
      FlashCard.create!(book:, book_html: html, areas_to_show: {}, items_to_remember: ["Alpha"])
    end
  end
end
