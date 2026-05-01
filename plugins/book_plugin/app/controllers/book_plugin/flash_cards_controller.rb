module BookPlugin
  class FlashCardsController < ApplicationController
    before_action :set_book

    def new
      @page_number = params[:page_number].presence&.to_i
      @book_html = find_or_create_book_html(@page_number) if @page_number
      if @page_number && @book_html.nil?
        @flash_card = @book.flash_cards.new
        flash.now[:alert] = "Could not extract page HTML. Please try again."
        render :new, status: :unprocessable_entity
        return
      end

      @flash_card = @book.flash_cards.new(book_html: @book_html)
    end

    def create
      @flash_card = @book.flash_cards.new(flash_card_params)
      @flash_card.areas_to_show = parse_areas_to_show(params.dig(:flash_card, :areas_to_show))
      @flash_card.items_to_remember = parse_items_to_remember(params.dig(:flash_card, :items_to_remember_text))

      if @flash_card.save
        redirect_to book_path(@book), notice: "Flash card created."
      else
        @page_number = @flash_card.book_html&.page_number
        @book_html = @flash_card.book_html
        flash.now[:alert] = "Could not create flash card."
        render :new, status: :unprocessable_entity
      end
    end

    private

    def set_book
      @book = Book.find(params[:book_id])
    end

    def find_or_create_book_html(page_number)
      cached_book_html = @book.book_htmls.find_by(page_number:)
      return cached_book_html if cached_book_html

      extraction_result = extract_page_html(page_number)
      return nil unless extraction_result.success?

      @book.book_htmls.create_or_find_by!(page_number:) do |book_html|
        book_html.html = extraction_result.html
      end
    rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid
      @book.book_htmls.find_by(page_number:)
    end

    def extract_page_html(page_number)
      return PdfHtmlExtractor::Result.new(html: nil, error_message: "Book file is not attached") unless @book.file.attached?

      @book.file.blob.open do |tempfile|
        PdfHtmlExtractor.call(pdf_path: tempfile.path, page_number:)
      end
    rescue StandardError => e
      PdfHtmlExtractor::Result.new(html: nil, error_message: e.message)
    end

    def flash_card_params
      params.require(:flash_card).permit(:book_html_id)
    end

    def parse_areas_to_show(raw_value)
      return {} if raw_value.blank?

      JSON.parse(raw_value)
    rescue JSON::ParserError
      {}
    end

    def parse_items_to_remember(raw_value)
      return [] if raw_value.blank?

      raw_value.split("\n").map(&:strip).reject(&:blank?)
    end
  end
end
