require "test_helper"

module BookPlugin
  class FlashCardsControllerTest < ActionDispatch::IntegrationTest
    test "new renders page picker" do
      book = Book.new(title: "Book")
      book.save!(validate: false)

      get "/books/books/#{book.id}/flash_cards/new"
      assert_response :success
      assert_select "input[name='page_number']"
    end

    test "new with page number creates book html and renders html content" do
      book = Book.new(title: "Book")
      book.save!(validate: false)

      get "/books/books/#{book.id}/flash_cards/new", params: { page_number: 3 }
      assert_response :success
      assert_equal 1, BookHtml.where(book:, page_number: 3).count
      assert_select ".book-html-preview", /Mock HTML for page 3/
    end

    test "create persists flash card" do
      book = Book.new(title: "Book")
      book.save!(validate: false)
      book_html = BookHtml.create!(book:, page_number: 2, html: "<p>Page 2</p>")

      assert_difference("FlashCard.count", 1) do
        post "/books/books/#{book.id}/flash_cards", params: {
          flash_card: {
            book_html_id: book_html.id,
            areas_to_show: "{\"x\":1}",
            items_to_remember_text: "alpha\nbeta"
          }
        }
      end

      assert_redirected_to "/books/books/#{book.id}"
    end
  end
end
