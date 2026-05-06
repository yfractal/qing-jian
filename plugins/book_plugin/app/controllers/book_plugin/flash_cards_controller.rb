module BookPlugin
  class FlashCardsController < ApplicationController
    before_action :set_book
    before_action :set_flash_card, only: [:edit, :update, :destroy]

    def index
      @flash_cards = @book.flash_cards.includes(:book_html).order(created_at: :desc)
    end

    def new
      @page_number, invalid_page_number = parse_page_number(params[:page_number])
      if invalid_page_number
        @flash_card = @book.flash_cards.new
        flash.now[:alert] = "Page number must be an integer greater than or equal to 1."
        render :new, status: :unprocessable_entity
        return
      end

      if @page_number
        @book_html = @book.book_htmls.find_by(page_number: @page_number) ||
          FindOrCreateBookHtml.call(book: @book, page_number: @page_number)
      end
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
      @flash_card.vector_adjustments = parse_vector_adjustments(params.dig(:flash_card, :vector_adjustments))

      if @flash_card.save
        redirect_to book_path(@book), notice: "Flash card created."
      else
        @page_number = @flash_card.book_html&.page_number
        @book_html = @flash_card.book_html
        flash.now[:alert] = "Could not create flash card."
        render :new, status: :unprocessable_entity
      end
    end

    def edit
      @book_html = @flash_card.book_html
    end

    def update
      @flash_card.assign_attributes(flash_card_params)
      @flash_card.areas_to_show = parse_areas_to_show(params.dig(:flash_card, :areas_to_show))
      @flash_card.items_to_remember = parse_items_to_remember(params.dig(:flash_card, :items_to_remember_text))
      @flash_card.vector_adjustments = parse_vector_adjustments(params.dig(:flash_card, :vector_adjustments))

      if @flash_card.save
        redirect_to book_flash_cards_path(@book), notice: "Flash card updated."
      else
        @book_html = @flash_card.book_html
        flash.now[:alert] = "Could not update flash card."
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      @flash_card.destroy!
      redirect_to book_flash_cards_path(@book), notice: "Flash card deleted."
    end

    private

    def set_flash_card
      @flash_card = @book.flash_cards.find(params[:id])
    end

    def set_book
      @book = Book.find(params[:book_id])
    end

    def flash_card_params
      params.require(:flash_card).permit(:book_html_id)
    end

    def parse_page_number(raw_value)
      return [nil, false] if raw_value.blank?

      parsed_value = raw_value.is_a?(String) ? Integer(raw_value, 10) : Integer(raw_value)
      return [nil, true] if parsed_value < 1

      [parsed_value, false]
    rescue ArgumentError, TypeError
      [nil, true]
    end

    def parse_areas_to_show(raw_value)
      return {} if raw_value.blank?

      JSON.parse(raw_value)
    rescue JSON::ParserError
      {}
    end

    def parse_items_to_remember(raw_value)
      return [] if raw_value.blank?

      stripped = raw_value.strip
      parsed = JSON.parse(stripped)
      return parsed if parsed.is_a?(Array)

      []
    rescue JSON::ParserError
      stripped.split(/\r?\n/, -1).map(&:strip).reject(&:blank?)
    end

    def parse_vector_adjustments(raw_value)
      return [] if raw_value.blank?

      parsed = JSON.parse(raw_value)
      return [] unless parsed.is_a?(Array)

      parsed.filter_map do |entry|
        next unless entry.is_a?(Hash)

        path_id = entry["path_id"].to_s
        next if path_id.blank?

        {
          "path_id" => path_id,
          "dx" => entry["dx"].to_f,
          "dy" => entry["dy"].to_f
        }
      end
    rescue JSON::ParserError
      []
    end
  end
end
