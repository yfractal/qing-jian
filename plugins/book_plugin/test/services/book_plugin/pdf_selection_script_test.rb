# frozen_string_literal: true

require "test_helper"
require "open3"

module BookPlugin
  class PdfSelectionScriptTest < ActiveSupport::TestCase
    test "build matches python build_selection_js" do
      repo_root = BookPlugin::Engine.root.join("..", "..").expand_path
      scale = 1.25
      area = { "x0" => 1, "y0" => 2, "x1" => 3, "y1" => 4 }
      py = <<~PY
        import json, sys
        sys.path.insert(0, #{repo_root.to_s.inspect})
        from js_functions import build_selection_js
        sys.stdout.write(build_selection_js(#{scale}, #{area.to_json}))
      PY
      expected, err, st = Open3.capture3("python3", "-c", py)
      skip "python/js_functions unavailable: #{err}" unless st.success?

      actual = PdfSelectionScript.build(scale: scale, initial_area: area.symbolize_keys)
      assert_equal expected, actual
    end

    test "build with nil area uses null in script" do
      s = PdfSelectionScript.build(scale: 2.0, initial_area: nil)
      assert_includes s, "const SCALE = 2.0;"
      assert_includes s, "const INITIAL_AREA_PDF = null;"
      assert_includes s, "const INITIAL_PICKED_TEXT_GROUPS = null;"
    end
  end
end
