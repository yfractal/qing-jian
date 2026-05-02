require "test_helper"

module BookPlugin
  class BookHtmlTest < ActiveSupport::TestCase
    test "requires unique page number per book" do
      book = Book.new(title: "A")
      book.save!(validate: false)

      BookHtml.create!(book:, page_number: 1, layout: sample_layout)

      duplicate = BookHtml.new(book:, page_number: 1, layout: sample_layout)
      assert_not duplicate.valid?
      assert_includes duplicate.errors[:page_number], "has already been taken"
    end

    test "requires layout" do
      book = Book.new(title: "A")
      book.save!(validate: false)

      bh = BookHtml.new(book:, page_number: 1, layout: {})
      assert_not bh.valid?
      assert bh.errors.details[:layout].any?
    end

    test "renders html from stored layout with rendered_html" do
      book = Book.new(title: "A")
      book.save!(validate: false)

      bh = BookHtml.create!(book:, page_number: 1, layout: sample_layout)
      out = bh.rendered_html(load_js: false)

      assert_includes out, "Hello"
      assert_includes out, "width:150.0px"
    end

    private

    def sample_layout
      {
        "items" => [
          {
            "type" => "text",
            "text" => "Hello",
            "bbox" => [0.0, 0.0, 48.0, 14.0],
            "font_size" => 12.0
          }
        ],
        "width" => 100.0,
        "height" => 200.0
      }
    end
  end
end
