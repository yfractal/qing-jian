# frozen_string_literal: true

require "json"
require_relative "pdf_selection_script_literal"

module BookPlugin
  module PdfSelectionScript
    module_function

    def build(scale:, initial_area: nil, initial_picked_text_groups: nil, initial_vector_adjustments: nil,
              initial_text_adjustments: nil)
      initial_json =
        if initial_area.nil?
          "null"
        else
          JSON.generate(initial_area.stringify_keys)
        end

      groups_json =
        if initial_picked_text_groups.nil?
          "null"
        else
          JSON.generate(initial_picked_text_groups)
        end

      vector_json = JSON.generate(initial_vector_adjustments || [])
      text_adj_json = JSON.generate(initial_text_adjustments || [])

      BookPlugin::PdfSelectionScriptLiteral.body
        .sub("const SCALE = 1.0;", "const SCALE = #{scale.to_f};")
        .sub("const INITIAL_AREA_PDF = null;", "const INITIAL_AREA_PDF = #{initial_json};")
        .sub("const INITIAL_PICKED_TEXT_GROUPS = null;", "const INITIAL_PICKED_TEXT_GROUPS = #{groups_json};")
        .sub("const INITIAL_VECTOR_ADJUSTMENTS = [];", "const INITIAL_VECTOR_ADJUSTMENTS = #{vector_json};")
        .sub("const INITIAL_TEXT_ADJUSTMENTS = [];", "const INITIAL_TEXT_ADJUSTMENTS = #{text_adj_json};")
    end
  end
end
