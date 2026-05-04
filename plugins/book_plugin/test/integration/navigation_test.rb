require "test_helper"

class NavigationTest < ActionDispatch::IntegrationTest
  test "book pages render inside host app shell" do
    get "/books"
    assert_response :success
    assert_select "main.remember-page"
  end

  test "book pages render shared primary navigation" do
    get "/books"

    assert_response :success
    assert_select "nav.site-nav[aria-label='Primary navigation']" do
      assert_select "a.site-nav-brand[href='/']", text: /Qing Jian/
      assert_select "a.site-nav-link[href='/']", "Review"
      assert_select "a.site-nav-link[href='/today_words']", "Today"
      assert_select "a.site-nav-link[href='/words']", "Words"
      assert_select "a.site-nav-link[href='/words/statistics']", "Statistics"
      assert_select "a.site-nav-link.is-active[aria-current='page'][href='/books']", "Books"
      assert_select "a.site-nav-action[href='/words/new']", "Add word"
      assert_select "a.site-nav-action[href='/books/books/new']", "New book"
    end
  end

  test "book show page keeps Books nav link active" do
    book = BookPlugin::Book.new(title: "Active Book")
    book.file.attach(io: StringIO.new("%PDF-1.4 sample"), filename: "active.pdf", content_type: "application/pdf")
    book.save!

    get "/books/books/#{book.id}"

    assert_response :success
    assert_select "a.site-nav-link.is-active[aria-current='page'][href='/books']", "Books"
  end

  test "book show links to flash card creation page" do
    book = BookPlugin::Book.new(title: "Flow Book")
    book.file.attach(io: StringIO.new("%PDF-1.4 sample"), filename: "flow.pdf", content_type: "application/pdf")
    book.save!

    get "/books/books/#{book.id}"
    assert_response :success
    assert_select "a[href='/books/books/#{book.id}/flash_cards/new']", "Create flash card"
  end

  test "book show links to flash cards index" do
    book = BookPlugin::Book.new(title: "Flow Book")
    book.file.attach(io: StringIO.new("%PDF-1.4 sample"), filename: "flow.pdf", content_type: "application/pdf")
    book.save!

    get "/books/books/#{book.id}"
    assert_response :success
    assert_select "a[href='/books/books/#{book.id}/flash_cards']", "Flash cards"
  end

  test "primary nav omits Remember Flash Cards link on root" do
    get "/"

    assert_response :success
    assert_select "a.site-nav-link", text: "Remember Flash Cards", count: 0
  end

  test "primary nav includes Book flash review on book show with correct book id" do
    book = BookPlugin::Book.new(title: "Nav Book")
    book.file.attach(io: StringIO.new("%PDF-1.4 sample"), filename: "nav.pdf", content_type: "application/pdf")
    book.save!

    get "/books/books/#{book.id}"

    assert_response :success
    assert_select "a.site-nav-link[href='/books/books/#{book.id}/flash_cards/remember']", "Book flash review"
  end

  test "primary nav omits Book flash review on books index" do
    get "/books"

    assert_response :success
    assert_select "a.site-nav-link", text: "Book flash review", count: 0
  end

  test "Book flash review nav link is active on flash card remember page" do
    book = BookPlugin::Book.new(title: "Active Remember")
    book.file.attach(io: StringIO.new("%PDF-1.4 sample"), filename: "mem.pdf", content_type: "application/pdf")
    book.save!

    get "/books/books/#{book.id}/flash_cards/remember"

    assert_response :success
    assert_select "a.site-nav-link.is-active[aria-current='page'][href='/books/books/#{book.id}/flash_cards/remember']", "Book flash review"
    assert_select "a.site-nav-link.is-active[aria-current='page'][href='/books']", text: "Books", count: 0
  end
end
