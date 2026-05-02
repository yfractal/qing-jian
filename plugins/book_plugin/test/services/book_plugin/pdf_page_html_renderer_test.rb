# frozen_string_literal: true

require "test_helper"

module BookPlugin
  class PdfPageHtmlRendererTest < ActiveSupport::TestCase
    # 1x1 transparent PNG
    PNG_1X1 = Base64.decode64(
      "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="
    ).freeze

    test "renders text image vector and toolbar" do
      Dir.mktmpdir do |dir|
        img_path = File.join(dir, "img_0_0.png")
        File.binwrite(img_path, PNG_1X1)

        layout = [
          { "type" => "text", "text" => "Hello <world>", "bbox" => [10, 20, 50, 35], "font_size" => 12 },
          { "type" => "image", "file" => img_path, "bbox" => [0, 0, 10, 10] },
          {
            "type" => "vector",
            "bbox" => [0, 0, 100, 100],
            "paths" => [
              {
                "d" => "M 0 0 L 1 1",
                "stroke" => "rgb(0, 0, 0)",
                "stroke_width" => 1,
                "fill" => "none",
                "bbox" => [0, 0, 1, 1]
              }
            ]
          }
        ]

        html = PdfPageHtmlRenderer.render(
          layout: layout,
          width: 100,
          height: 200,
          scale: 1.5,
          area: nil,
          load_js: true
        )

        assert_includes html, "Hello &lt;world&gt;"
        assert_includes html, "img_0_0.png"
        refute_includes html, "data:image/png"
        assert_includes html, "vector-layer"
        assert_includes html, "btn-pick-area"
        assert_includes html, "const SCALE = 1.5;"
      end
    end
  end
end
