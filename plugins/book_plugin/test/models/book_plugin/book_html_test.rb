require "test_helper"
require "base64"
require "stringio"

module BookPlugin
  class BookHtmlTest < ActiveSupport::TestCase
    MINI_PNG = Base64.decode64(
      "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="
    ).freeze

    test "requires unique page number per book" do
      book = Book.new(title: "A")
      book.save!(validate: false)

      BookHtml.create!(book:, page_number: 1, html: "<p>first</p>")

      duplicate = BookHtml.new(book:, page_number: 1, html: "<p>dup</p>")
      assert_not duplicate.valid?
      assert_includes duplicate.errors[:page_number], "has already been taken"
    end

    test "allows many attached images" do
      book = Book.new(title: "A")
      book.save!(validate: false)

      book_html = BookHtml.create!(book:, page_number: 1, html: "<p>x</p>")
      book_html.images.attach(
        io: StringIO.new(MINI_PNG),
        filename: "a.png",
        content_type: "image/png"
      )
      book_html.images.attach(
        io: StringIO.new(MINI_PNG),
        filename: "b.png",
        content_type: "image/png"
      )
      book_html.reload

      assert_equal 2, book_html.images.count
    end
  end
end
