require "test_helper"

module BookPlugin
  class BooksControllerTest < ActionDispatch::IntegrationTest
    test "index shows books heading" do
      get "/books"
      assert_response :success
      assert_select "h1", "Books"
    end

    test "create persists book and redirects" do
      file = fixture_file_upload("sample.pdf", "application/pdf")

      assert_difference("BookPlugin::Book.count", 1) do
        post "/books/books", params: { book: { title: "New Book", description: "Desc", file: file } }
      end

      assert_redirected_to "/books/books/#{BookPlugin::Book.last.id}"
    end
  end
end
