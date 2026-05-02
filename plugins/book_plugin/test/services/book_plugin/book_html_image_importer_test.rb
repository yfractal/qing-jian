require "test_helper"
require "base64"

module BookPlugin
  class BookHtmlImageImporterTest < ActiveSupport::TestCase
    MINI_PNG = Base64.decode64(
      "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="
    ).freeze

    test "attaches images and rewrites img src to blob paths" do
      Rails.application.routes.default_url_options[:host] = "www.example.com"

      book = Book.new(title: "A")
      book.save!(validate: false)

      old_path = "/tmp/extract/img_0_0.png"
      html = %(<html><body><img src="#{old_path}"></body></html>)

      book_html = BookHtml.create!(book:, page_number: 1, html:)

      extraction = PdfHtmlExtractor::Result.new(
        html:,
        images: [{ filename: "img_0_0.png", data: MINI_PNG.dup }],
        error_message: nil
      )

      BookHtmlImageImporter.call(book_html:, extraction_result: extraction)
      book_html.reload

      assert_equal 1, book_html.images.count
      assert_match %r{/rails/active_storage/blobs/redirect/}, book_html.html
      refute_includes book_html.html, old_path
    end
  end
end
