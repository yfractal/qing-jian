require "test_helper"

module BookPlugin
  class BookHtmlTest < ActiveSupport::TestCase
    test "requires unique page number per book" do
      book = Book.new(title: "A")
      book.save!(validate: false)

      BookHtml.create!(book:, page_number: 1, html: "<p>first</p>")

      duplicate = BookHtml.new(book:, page_number: 1, html: "<p>dup</p>")
      assert_not duplicate.valid?
      assert_includes duplicate.errors[:page_number], "has already been taken"
    end
  end
end
