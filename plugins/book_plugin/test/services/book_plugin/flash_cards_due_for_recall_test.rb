require "test_helper"

module BookPlugin
  class FlashCardsDueForRecallTest < ActiveSupport::TestCase
    test "returns due flash cards for a book and excludes reviewed ids" do
      book = create_book
      due_card = create_flash_card(book:, text: "Due")
      future_card = create_flash_card(book:, text: "Future")
      future_card.recall_state.update!(due_day: Date.current + 1.day)

      result = FlashCardsDueForRecall.call(
        day: Date.current,
        book: book,
        excluding_flash_card_ids: [future_card.id]
      )

      assert_includes result, due_card
      assert_not_includes result, future_card
    end

    test "correct record increments remember times and sets next due day" do
      card = create_flash_card
      record = FlashCardRecallRecord.create!(flash_card: card, is_correct: true)

      card.recall_state.reload
      assert_equal 1, card.recall_state.remember_times
      assert_equal record.created_at.to_date + 2.days, card.recall_state.due_day
    end

    test "incorrect record leaves recall state unchanged" do
      card = create_flash_card
      original_due_day = card.recall_state.due_day

      FlashCardRecallRecord.create!(flash_card: card, is_correct: false)

      card.recall_state.reload
      assert_equal 0, card.recall_state.remember_times
      assert_equal original_due_day, card.recall_state.due_day
    end

    test "sixth correct answer completes recall schedule" do
      card = create_flash_card
      card.recall_state.update!(remember_times: 5, due_day: Date.current)

      FlashCardRecallRecord.create!(flash_card: card, is_correct: true)

      card.recall_state.reload
      assert_equal 6, card.recall_state.remember_times
      assert_nil card.recall_state.due_day
    end

    private

    def create_book
      book = Book.new(title: "Book")
      book.save!(validate: false)
      book
    end

    def create_flash_card(book: create_book, text: "Text")
      html = BookHtml.create!(
        book:,
        page_number: book.book_htmls.count + 1,
        layout: {
          "width" => 100.0,
          "height" => 200.0,
          "items" => [
            { "type" => "text", "text" => text, "bbox" => [10, 20, 50, 35], "font_size" => 12 }
          ]
        }
      )
      FlashCard.create!(book:, book_html: html, areas_to_show: {}, items_to_remember: [text])
    end
  end
end
