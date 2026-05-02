# frozen_string_literal: true

module BookPlugin
  module PdfSelectionScriptLiteral
    class << self
      def body
        @body ||= File.read(
          File.join(__dir__, "pdf_selection_script.js.txt"),
          encoding: Encoding::UTF_8
        )
      end
    end
  end
end
