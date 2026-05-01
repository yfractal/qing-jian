require "test_helper"

class NavigationTest < ActionDispatch::IntegrationTest
  test "book pages render inside host app shell" do
    get "/books"
    assert_response :success
    assert_select "main.remember-page"
  end

  test "book show links to flash card creation page" do
    book = BookPlugin::Book.new(title: "Flow Book")
    book.file.attach(io: StringIO.new("%PDF-1.4 sample"), filename: "flow.pdf", content_type: "application/pdf")
    book.save!

    get "/books/books/#{book.id}"
    assert_response :success
    assert_select "a[href='/books/books/#{book.id}/flash_cards/new']", "Create flash card"
  end
end
