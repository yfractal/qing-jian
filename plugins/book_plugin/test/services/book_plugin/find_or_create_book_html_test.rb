require "test_helper"
require "base64"
require "tempfile"
require "stringio"

module BookPlugin
  class FindOrCreateBookHtmlTest < ActiveSupport::TestCase
    PNG_1X1 = Base64.decode64(
      "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="
    ).freeze

    def with_singleton_stub(target, method_name, replacement)
      eigenclass = class << target; self; end
      original_defined = target.respond_to?(method_name, true)
      original_method = target.method(method_name) if original_defined

      eigenclass.send(:define_method, method_name, &replacement)
      yield
    ensure
      if original_defined
        eigenclass.send(:define_method, method_name, original_method.to_proc)
      else
        eigenclass.send(:remove_method, method_name)
      end
    end

    test "returns cached book html without extracting" do
      book = create_book_with_pdf
      cached = BookHtml.create!(book:, page_number: 3, layout: text_layout)

      with_singleton_stub(PdfLayoutExtractor, :call, ->(**) { raise "extractor should not be called on cache hit" }) do
        assert_equal cached, FindOrCreateBookHtml.call(book:, page_number: 3)
      end
    end

    test "extracts layout, uploads image files, and stores blob ids" do
      book = create_book_with_pdf
      image_file = Tempfile.new(["img_19_0", ".png"])
      image_file.binmode
      image_file.write(PNG_1X1)
      image_file.flush

      result = PdfLayoutExtractor::Result.new(
        layout: [
          { "type" => "text", "text" => "Hello", "bbox" => [10, 20, 40, 32], "font_size" => 12 },
          { "type" => "image", "file" => image_file.path, "bbox" => [0.0, 676.0, 54.25, 690.85] }
        ],
        width: 300.0,
        height: 700.0,
        error_message: nil
      )

      with_singleton_stub(PdfLayoutExtractor, :call, ->(**) { result }) do
        book_html = FindOrCreateBookHtml.call(book:, page_number: 19)

        assert_predicate book_html, :persisted?
        image_item = book_html.layout.fetch("items").detect { |item| item["type"] == "image" }
        assert_nil image_item["file"]
        assert ActiveStorage::Blob.exists?(image_item.fetch("active_storage_blob_id"))
        assert_equal 300.0, book_html.layout.fetch("width")
        assert_equal 700.0, book_html.layout.fetch("height")
      end
    ensure
      image_file&.close!
    end

    test "returns nil when extractor fails" do
      book = create_book_with_pdf
      result = PdfLayoutExtractor::Result.new(layout: nil, width: nil, height: nil, error_message: "boom")

      with_singleton_stub(PdfLayoutExtractor, :call, ->(**) { result }) do
        assert_nil FindOrCreateBookHtml.call(book:, page_number: 7)
      end
    end

    private

    def create_book_with_pdf
      book = Book.new(title: "Book")
      book.save!(validate: false)
      book.file.attach(
        io: StringIO.new("%PDF-1.4\n1 0 obj\n<<>>\nendobj\ntrailer\n<<>>\n%%EOF\n"),
        filename: "book.pdf",
        content_type: "application/pdf"
      )
      book
    end

    def text_layout
      {
        "width" => 100.0,
        "height" => 200.0,
        "items" => [
          { "type" => "text", "text" => "Cached", "bbox" => [1, 2, 3, 4], "font_size" => 10 }
        ]
      }
    end
  end
end
