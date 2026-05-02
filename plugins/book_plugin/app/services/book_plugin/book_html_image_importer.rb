require "stringio"

module BookPlugin
  class BookHtmlImageImporter
    class << self
      def call(book_html:, extraction_result:)
        return unless extraction_result.success?
        return if extraction_result.images.blank?

        book_html.with_lock do
          next if book_html.images.any?

          blobs = extraction_result.images.map do |img|
            {
              io: StringIO.new(img.fetch(:data)),
              filename: img.fetch(:filename),
              content_type: "image/png"
            }
          end
          book_html.images.attach(blobs)
          book_html.reload

          rewriter = build_src_rewriter(extraction_result, book_html)
          book_html.update!(html: rewriter.call(book_html.html))
        end
      end

      private

      def build_src_rewriter(extraction_result, book_html)
        srcs = extraction_result.html.scan(/<img[^>]+src=["']([^"']+)["']/i).flatten
        blob_list = book_html.images.blobs.to_a
        replacements = srcs.zip(blob_list).to_h

        lambda do |html|
          replacements.reduce(html) do |memo, (old_src, blob)|
            memo.gsub(old_src, Rails.application.routes.url_helpers.rails_blob_path(blob, only_path: true))
          end
        end
      end
    end
  end
end
