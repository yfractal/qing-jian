require "test_helper"
require "base64"

module BookPlugin
  class FlashCardsControllerTest < ActionDispatch::IntegrationTest
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

    test "new renders page picker" do
      book = Book.new(title: "Book")
      book.save!(validate: false)

      get "/books/books/#{book.id}/flash_cards/new"
      assert_response :success
      assert_select "input[name='page_number']"
    end

    test "new with page number reuses cached html without extractor call" do
      book = create_book_with_pdf
      BookHtml.create!(book:, page_number: 3, html: "<article>Cached HTML for page 3</article>")

      with_singleton_stub(PdfHtmlExtractor, :call, ->(**) { raise "extractor should not be called on cache hit" }) do
        get "/books/books/#{book.id}/flash_cards/new", params: { page_number: 3 }
      end

      assert_response :success
      assert_equal 1, BookHtml.where(book:, page_number: 3).count
      assert_select "iframe.book-html-preview-frame[srcdoc*='Cached HTML for page 3']"
    end

    test "new with page number cache miss calls extractor and persists html" do
      book = create_book_with_pdf
      extractor_called = false
      extractor_page_number = nil
      extractor_load_js = nil
      pdf_path_present = nil
      pdf_header = nil

      with_singleton_stub(PdfHtmlExtractor, :call, lambda { |pdf_path:, page_number:, load_js:, **|
        extractor_called = true
        extractor_page_number = page_number
        extractor_load_js = load_js
        pdf_path_present = File.exist?(pdf_path)
        pdf_header = File.binread(pdf_path, 8)

        PdfHtmlExtractor::Result.new(html: "<article>Extracted HTML for page 3</article>", images: [], error_message: nil)
      }) do
        get "/books/books/#{book.id}/flash_cards/new", params: { page_number: 3 }
      end

      assert_response :success
      assert_equal true, extractor_called
      assert_equal 3, extractor_page_number
      assert_equal false, extractor_load_js
      assert_equal true, pdf_path_present
      assert_equal "%PDF-1.4", pdf_header
      assert_equal 1, BookHtml.where(book:, page_number: 3).count
      assert_select "iframe.book-html-preview-frame[srcdoc*='Extracted HTML for page 3']"
    end

    test "new with page number shows alert on extractor failure" do
      book = create_book_with_pdf

      with_singleton_stub(PdfHtmlExtractor, :call, lambda { |**|
        PdfHtmlExtractor::Result.new(html: nil, images: [], error_message: "boom")
      }) do
        assert_no_difference("BookHtml.count") do
          get "/books/books/#{book.id}/flash_cards/new", params: { page_number: 7 }
        end
      end

      assert_response :unprocessable_entity
      assert_includes @response.body, "Could not extract page HTML. Please try again."
      assert_select "input[name='page_number']"
    end

    test "new with non numeric page number shows validation alert without extraction" do
      book = create_book_with_pdf

      with_singleton_stub(PdfHtmlExtractor, :call, ->(**) { raise "extractor should not be called for invalid page number" }) do
        assert_no_difference("BookHtml.count") do
          get "/books/books/#{book.id}/flash_cards/new", params: { page_number: "abc" }
        end
      end

      assert_response :unprocessable_entity
      assert_includes @response.body, "Page number must be an integer greater than or equal to 1."
      assert_select "input[name='page_number']"
    end

    test "new with zero page number shows validation alert without extraction" do
      book = create_book_with_pdf

      with_singleton_stub(PdfHtmlExtractor, :call, ->(**) { raise "extractor should not be called for invalid page number" }) do
        assert_no_difference("BookHtml.count") do
          get "/books/books/#{book.id}/flash_cards/new", params: { page_number: 0 }
        end
      end

      assert_response :unprocessable_entity
      assert_includes @response.body, "Page number must be an integer greater than or equal to 1."
      assert_select "input[name='page_number']"
    end

    test "new with page number reuses just-created row under uniqueness contention" do
      book = create_book_with_pdf

      with_singleton_stub(PdfHtmlExtractor, :call, lambda { |**|
        BookHtml.create!(
          book:,
          page_number: 8,
          html: "<article>Concurrent HTML for page 8</article>"
        )
        PdfHtmlExtractor::Result.new(html: "<article>Late extractor HTML</article>", images: [], error_message: nil)
      }) do
        get "/books/books/#{book.id}/flash_cards/new", params: { page_number: 8 }
      end

      assert_response :success
      assert_equal 1, BookHtml.where(book:, page_number: 8).count
      assert_select "iframe.book-html-preview-frame[srcdoc*='Concurrent HTML for page 8']"
    end

    test "new persists book html images when extraction returns payloads" do
      book = create_book_with_pdf
      png = Base64.decode64(
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="
      )
      src = "/var/tmp/img_0_0.png"
      html = %(<html><body><img src="#{src}"></body></html>)

      with_singleton_stub(PdfHtmlExtractor, :call, lambda { |**|
        PdfHtmlExtractor::Result.new(
          html:,
          images: [{ filename: "img_0_0.png", data: png }],
          error_message: nil
        )
      }) do
        get "/books/books/#{book.id}/flash_cards/new", params: { page_number: 1 }
      end

      assert_response :success

      html_record = book.book_htmls.find_by!(page_number: 1)
      assert_predicate html_record.images, :any?
      assert_includes html_record.html, "/rails/active_storage/"
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
  end
end
