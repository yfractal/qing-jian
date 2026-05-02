module BookPlugin
  class FlashCardRememberController < ApplicationController
    before_action :set_book

    def index
      @reviewed_flash_card_ids = reviewed_flash_card_ids
      load_progress_counts!

      return if load_result_state

      due_cards = FlashCardsDueForRecall.call(day: Date.current, book: @book)
      filtered_due_cards = FlashCardsDueForRecall.call(
        day: Date.current,
        book: @book,
        excluding_flash_card_ids: @reviewed_flash_card_ids
      )

      if @reviewed_flash_card_ids.any? && filtered_due_cards.none?
        redirect_to book_remember_book_flash_cards_path(@book), notice: pass_cleared_notice(due_cards)
        return
      end

      @flash_card = filtered_due_cards.includes(:book_html).order(Arel.sql("RANDOM()")).first
      @flash_card_recall_record = FlashCardRecallRecord.new(flash_card: @flash_card) if @flash_card
    end

    private

    def set_book
      @book = Book.find(params[:book_id])
    end

    def reviewed_flash_card_ids
      params[:reviewed_flash_card_ids].to_s.split(",").filter_map do |flash_card_id|
        parsed_id = Integer(flash_card_id, exception: false)
        parsed_id if parsed_id&.positive?
      end.uniq
    end

    def load_result_state
      @result_record = FlashCardRecallRecord
        .joins(:flash_card)
        .where(book_plugin_flash_cards: { book_id: @book.id })
        .find_by(id: params[:result_record_id])
      return false unless @result_record

      @flash_card = @result_record.flash_card
      @flash_card_recall_record = @result_record
      @next_flash_card_path = book_remember_book_flash_cards_path(
        @book,
        reviewed_flash_card_ids: (@reviewed_flash_card_ids + [@flash_card.id]).uniq.join(",")
      )

      true
    end

    def result_state?
      @result_record.present?
    end
    helper_method :result_state?

    def pass_cleared_notice(due_cards)
      if due_cards.exists?
        "Starting another flash card recall pass for cards still due."
      else
        "All flash cards recalled for today."
      end
    end

    def load_progress_counts!
      current_due_card_ids = FlashCardsDueForRecall.call(day: Date.current, book: @book).pluck(:id)
      remembered_today_card_ids = @book.flash_card_recall_records
        .where(is_correct: true, created_at: Time.zone.today.all_day)
        .distinct
        .pluck(:flash_card_id)
      progress_card_ids = current_due_card_ids | remembered_today_card_ids

      @remember_total_count = progress_card_ids.size
      @remembered_count = remembered_today_card_ids.size
      @remaining_count = current_due_card_ids.size
      @progress_percent = if @remember_total_count.zero?
        0
      else
        ((@remembered_count.to_f / @remember_total_count) * 100).round
      end
    end
  end
end
