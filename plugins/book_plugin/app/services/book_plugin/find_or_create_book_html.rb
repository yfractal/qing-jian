module BookPlugin
  class FindOrCreateBookHtml
    class << self
      def call(book:, page_number:)
        new(book:, page_number:).call
      end
    end

    def initialize(book:, page_number:)
      @book = book
      @page_number = page_number
    end

    def call
      cached_book_html = @book.book_htmls.find_by(page_number: @page_number)
      return cached_book_html if cached_book_html

      extraction_result = extract_layout
      return nil unless extraction_result.success?

      layout_payload = build_layout_payload(extraction_result)
      @book.book_htmls.create_or_find_by!(page_number: @page_number) do |book_html|
        book_html.layout = layout_payload
      end
    rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid
      @book.book_htmls.find_by(page_number: @page_number)
    end

    private

    def extract_layout
      unless @page_number.is_a?(Integer) && @page_number >= 1
        return PdfLayoutExtractor::Result.new(layout: nil, width: nil, height: nil, error_message: "Page number must be an integer greater than or equal to 1")
      end

      return PdfLayoutExtractor::Result.new(layout: nil, width: nil, height: nil, error_message: "Book file is not attached") unless @book.file.attached?

      @book.file.blob.open do |tempfile|
        PdfLayoutExtractor.call(pdf_path: tempfile.path, page_number: @page_number)
      end
    rescue StandardError => e
      PdfLayoutExtractor::Result.new(layout: nil, width: nil, height: nil, error_message: e.message)
    end

    def build_layout_payload(extraction_result)
      {
        "width" => extraction_result.width,
        "height" => extraction_result.height,
        "items" => extraction_result.layout.map { |item| normalize_layout_item(item) }
      }
    end

    def normalize_layout_item(item)
      if item["type"] == "image" && item["__pending_upload__"].is_a?(Hash)
        pending = item.fetch("__pending_upload__")
        data = pending["data"]
        return item.except("file", "__pending_upload__") if data.blank?

        filename = pending["filename"].to_s.presence || "image.png"
        io = StringIO.new(data.b)
        blob = ActiveStorage::Blob.create_and_upload!(
          io:,
          filename:,
          content_type: content_type_for_image_filename(filename)
        )
        return item.except("file", "__pending_upload__").merge("active_storage_blob_id" => blob.id)
      end

      return item unless item["type"] == "image" && item["file"].present?

      image_path = item.fetch("file")
      blob = File.open(image_path, "rb") do |io|
        ActiveStorage::Blob.create_and_upload!(
          io:,
          filename: File.basename(image_path),
          content_type: content_type_for_image_filename(File.basename(image_path))
        )
      end
      item.except("file").merge("active_storage_blob_id" => blob.id)
    end

    def content_type_for_image_filename(filename)
      case File.extname(filename).downcase
      when ".png" then "image/png"
      when ".jpg", ".jpeg" then "image/jpeg"
      when ".gif" then "image/gif"
      when ".webp" then "image/webp"
      else "application/octet-stream"
      end
    end
  end
end
