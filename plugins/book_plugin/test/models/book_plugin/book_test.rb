require "test_helper"

module BookPlugin
  class BookTest < ActiveSupport::TestCase
    test "requires title" do
      book = Book.new(description: "Notes")
      book.file.attach(
        io: StringIO.new("%PDF-1.4 sample"),
        filename: "sample.pdf",
        content_type: "application/pdf"
      )

      assert_not book.valid?
      assert_includes book.errors[:title], "can't be blank"
    end

    test "requires attached pdf file" do
      book = Book.new(title: "Ruby Patterns", description: "Notes")

      assert_not book.valid?
      assert_includes book.errors[:file], "must be attached"
    end

    test "rejects non-pdf attachment" do
      book = Book.new(title: "Ruby Patterns", description: "Notes")
      book.file.attach(
        io: StringIO.new("not pdf"),
        filename: "sample.txt",
        content_type: "text/plain"
      )

      assert_not book.valid?
      assert_includes book.errors[:file], "must be a PDF"
    end
  end
end
