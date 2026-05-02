require "test_helper"
require "base64"
require "tempfile"

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

    test "new with page number reuses cached layout without finder call" do
      book = create_book_with_pdf
      BookHtml.create!(book:, page_number: 3, layout: sample_layout("Cached page 3"))

      with_singleton_stub(FindOrCreateBookHtml, :call, ->(**) { raise "finder should not be called on cache hit" }) do
        get "/books/books/#{book.id}/flash_cards/new", params: { page_number: 3 }
      end

      assert_response :success
      assert_equal 1, BookHtml.where(book:, page_number: 3).count
      assert_select "iframe.book-html-preview-frame[srcdoc*='Cached page 3']"
    end

    test "new with page number includes flash card preview parent script" do
      book = create_book_with_pdf
      BookHtml.create!(book:, page_number: 3, layout: sample_layout("Cached page 3"))

      get "/books/books/#{book.id}/flash_cards/new", params: { page_number: 3 }

      assert_response :success
      assert_select 'script[src*="flash_card_preview_parent"]'
      assert_select "textarea#flash_card_areas_to_show"
      assert_select "textarea#flash_card_items_to_remember_text"
    end

    test "new with page number cache miss calls finder" do
      book = create_book_with_pdf
      finder_called = false
      received_book = nil
      received_page = nil

      with_singleton_stub(FindOrCreateBookHtml, :call, lambda { |**kw|
        finder_called = true
        received_book = kw[:book]
        received_page = kw[:page_number]
        BookHtml.create!(
          book: kw[:book],
          page_number: 3,
          layout: {
            "width" => 100.0,
            "height" => 200.0,
            "items" => [
              { "type" => "text", "text" => "Extracted page 3", "bbox" => [10, 20, 50, 35], "font_size" => 12 }
            ]
          }
        )
      }) do
        get "/books/books/#{book.id}/flash_cards/new", params: { page_number: 3 }
      end

      assert_response :success
      assert_equal true, finder_called
      assert_equal book, received_book
      assert_equal 3, received_page
      assert_select "iframe.book-html-preview-frame[srcdoc*='Extracted page 3']"
    end

    test "new with page number shows alert on extractor failure" do
      book = create_book_with_pdf

      with_singleton_stub(FindOrCreateBookHtml, :call, ->(**) { nil }) do
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

      with_singleton_stub(FindOrCreateBookHtml, :call, ->(**) { raise "finder should not be called for invalid page number" }) do
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

      with_singleton_stub(FindOrCreateBookHtml, :call, ->(**) { raise "finder should not be called for invalid page number" }) do
        assert_no_difference("BookHtml.count") do
          get "/books/books/#{book.id}/flash_cards/new", params: { page_number: 0 }
        end
      end

      assert_response :unprocessable_entity
      assert_includes @response.body, "Page number must be an integer greater than or equal to 1."
      assert_select "input[name='page_number']"
    end

    test "new persists layout image blobs when extraction returns image paths" do
      book = create_book_with_pdf
      png = Base64.decode64(
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="
      )

      Tempfile.create(["img_0_0", ".png"]) do |f|
        f.binmode
        f.write(png)
        f.flush

        with_singleton_stub(PdfLayoutExtractor, :call, lambda { |**|
          PdfLayoutExtractor::Result.new(
            layout: [
              { "type" => "image", "file" => f.path, "bbox" => [0, 0, 10, 10] }
            ],
            width: 100.0,
            height: 200.0,
            error_message: nil
          )
        }) do
          get "/books/books/#{book.id}/flash_cards/new", params: { page_number: 1 }
        end
      end

      assert_response :success

      html_record = book.book_htmls.find_by!(page_number: 1)
      image_item = html_record.layout.fetch("items").find { |item| item["type"] == "image" }
      assert image_item["active_storage_blob_id"].present?
      assert_nil image_item["file"]
      assert_select "iframe.book-html-preview-frame[srcdoc*='/rails/active_storage/']"
    end

    test "create persists flash card" do
      book = Book.new(title: "Book")
      book.save!(validate: false)
      book_html = BookHtml.create!(book:, page_number: 2, layout: sample_layout("Page 2"))

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

    test "index links to remember flash cards" do
      book = Book.new(title: "Book")
      book.save!(validate: false)

      get "/books/books/#{book.id}/flash_cards"

      assert_response :success
      assert_select "a[href='/books/books/#{book.id}/flash_cards/remember']", "Remember flash cards"
    end

    test "index lists flash cards for book with edit link" do
      book = Book.new(title: "Book")
      book.save!(validate: false)
      book_html = BookHtml.create!(book:, page_number: 2, layout: sample_layout("Page 2"))
      card = FlashCard.create!(book:, book_html:, areas_to_show: {}, items_to_remember: [])

      get "/books/books/#{book.id}/flash_cards"

      assert_response :success
      assert_select "a[href='/books/books/#{book.id}/flash_cards/#{card.id}/edit']", "Edit"
    end

    test "index shows empty message when book has no flash cards" do
      book = Book.new(title: "Empty")
      book.save!(validate: false)

      get "/books/books/#{book.id}/flash_cards"

      assert_response :success
      assert_includes @response.body, "No flash cards yet"
    end

    test "edit renders reused form and preview" do
      book = Book.new(title: "Book")
      book.save!(validate: false)
      book_html = BookHtml.create!(book:, page_number: 3, layout: sample_layout("Edit page"))
      card = FlashCard.create!(
        book:,
        book_html:,
        areas_to_show: { "a" => 1 },
        items_to_remember: ["line1"]
      )

      get "/books/books/#{book.id}/flash_cards/#{card.id}/edit"

      assert_response :success
      assert_select 'script[src*="flash_card_preview_parent"]'
      assert_select "iframe.book-html-preview-frame[srcdoc*='Edit page']"
      assert_select "textarea#flash_card_areas_to_show", text: /\"a\"/
      assert_select "input[type=submit][value='Update flash card']"
    end

    test "update changes flash card and redirects to index" do
      book = Book.new(title: "Book")
      book.save!(validate: false)
      book_html = BookHtml.create!(book:, page_number: 4, layout: sample_layout("P4"))
      card = FlashCard.create!(book:, book_html:, areas_to_show: {}, items_to_remember: [])

      patch "/books/books/#{book.id}/flash_cards/#{card.id}", params: {
        flash_card: {
          book_html_id: book_html.id,
          areas_to_show: "{\"k\":2}",
          items_to_remember_text: "x\ny"
        }
      }

      assert_redirected_to "/books/books/#{book.id}/flash_cards"
      card.reload
      assert_equal({ "k" => 2 }, card.areas_to_show)
      assert_equal %w[x y], card.items_to_remember
    end

    test "destroy removes flash card and redirects to index" do
      book = Book.new(title: "Book")
      book.save!(validate: false)
      book_html = BookHtml.create!(book:, page_number: 1, layout: sample_layout)
      card = FlashCard.create!(book:, book_html:, areas_to_show: {}, items_to_remember: [])

      assert_difference("FlashCard.count", -1) do
        delete "/books/books/#{book.id}/flash_cards/#{card.id}"
      end

      assert_redirected_to "/books/books/#{book.id}/flash_cards"
    end

    private

    def sample_layout(text = "Page text")
      {
        "width" => 100.0,
        "height" => 200.0,
        "items" => [
          { "type" => "text", "text" => text, "bbox" => [10, 20, 50, 35], "font_size" => 12 }
        ]
      }
    end

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
