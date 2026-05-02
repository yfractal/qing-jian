# frozen_string_literal: true

require "json"
require_relative "pdf_selection_script_literal"

module BookPlugin
  module PdfSelectionScript
    module_function

    def build(scale:, initial_area: nil)
      initial_json =
        if initial_area.nil?
          "null"
        else
          JSON.generate(initial_area.stringify_keys)
        end

      BookPlugin::PdfSelectionScriptLiteral.body
        .sub("const SCALE = 1.0;", "const SCALE = #{scale.to_f};")
        .sub("const INITIAL_AREA_PDF = null;", "const INITIAL_AREA_PDF = #{initial_json};")
    end
  end
end
