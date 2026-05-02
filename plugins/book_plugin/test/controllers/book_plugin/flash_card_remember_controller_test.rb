require "test_helper"

module BookPlugin
  class FlashCardRememberControllerTest < ActionDispatch::IntegrationTest
    test "index shows one due flash card" do
      book = create_book
      card = create_flash_card(book:, text: "Remember this")

      get "/books/books/#{book.id}/flash_cards/remember"

      assert_response :success
      assert_select "h1", "Remember Flash Cards"
      assert_select "iframe.flash-card-study-frame"
      assert_select "input[name='flash_card_recall_record[flash_card_id]'][value='#{card.id}']", visible: false
    end

    test "index excludes cards already reviewed in this pass" do
      book = create_book
      reviewed_card = create_flash_card(book:, text: "Reviewed")
      next_card = create_flash_card(book:, text: "Next")

      get "/books/books/#{book.id}/flash_cards/remember", params: {
        reviewed_flash_card_ids: reviewed_card.id.to_s
      }

      assert_response :success
      assert_select "input[name='flash_card_recall_record[flash_card_id]'][value='#{next_card.id}']", visible: false
    end

    test "index restarts pass when reviewed ids hide remaining due cards" do
      book = create_book
      card = create_flash_card(book:, text: "Again")

      get "/books/books/#{book.id}/flash_cards/remember", params: {
        reviewed_flash_card_ids: card.id.to_s
      }

      assert_redirected_to "/books/books/#{book.id}/flash_cards/remember"
      assert_equal "Starting another flash card recall pass for cards still due.", flash[:notice]
    end

    test "result state renders next flash card path" do
      book = create_book
      card = create_flash_card(book:, text: "Done")
      record = FlashCardRecallRecord.create!(flash_card: card, is_correct: true)

      get "/books/books/#{book.id}/flash_cards/remember", params: {
        result_record_id: record.id
      }

      assert_response :success
      expected_href = "/books/books/#{book.id}/flash_cards/remember?reviewed_flash_card_ids=#{card.id}"
      assert_select "a[href=?]", expected_href, text: "Next flash card"
    end

    private

    def create_book
      book = Book.new(title: "Book")
      book.save!(validate: false)
      book
    end

    def create_flash_card(book:, text:)
      html = BookHtml.create!(
        book:,
        page_number: book.book_htmls.count + 1,
        layout: {
          "width" => 100.0,
          "height" => 200.0,
          "items" => [
            { "type" => "text", "text" => text, "bbox" => [10, 20, 50, 35], "font_size" => 12 }
          ]
        }
      )
      FlashCard.create!(book:, book_html: html, areas_to_show: {}, items_to_remember: [text])
    end
  end
end
