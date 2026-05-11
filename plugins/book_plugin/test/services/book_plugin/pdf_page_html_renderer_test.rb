# frozen_string_literal: true

require "test_helper"
require "stringio"

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
        assert_includes html, "btn-drag-items"
        assert_includes html, "Drag Items"
        assert_includes html, "const SCALE = 1.5;"
      end
    end

    test "remaps white vector paint to black for visibility on white page" do
      layout = [
        {
          "type" => "vector",
          "bbox" => [0, 0, 10, 10],
          "paths" => [
            {
              "d" => "M 0 0 L 9 9",
              "stroke" => "rgb(255, 255, 255)",
              "stroke_width" => 1,
              "fill" => "none",
              "bbox" => [0, 0, 9, 9]
            }
          ]
        }
      ]

      html = PdfPageHtmlRenderer.render(
        layout: layout,
        width: 10,
        height: 10,
        scale: 1,
        area: nil,
        load_js: false
      )

      assert_includes html, 'stroke="#000000"'
      assert_includes html, 'fill="none"'
    end

    test "renders image from active storage blob id" do
      blob = ActiveStorage::Blob.create_and_upload!(
        io: StringIO.new(PNG_1X1),
        filename: "img_19_0.png",
        content_type: "image/png"
      )
      layout = [
        { "type" => "image", "active_storage_blob_id" => blob.id, "bbox" => [0, 0, 10, 10] }
      ]

      html = PdfPageHtmlRenderer.render(
        layout:,
        width: 100,
        height: 200,
        scale: 1.5,
        area: nil,
        load_js: false
      )

      assert_includes html, "/rails/active_storage/"
      assert_includes html, "img_19_0.png"
      refute_includes html, "active_storage_blob_id"
    end

    test "embeds initial area and picked text groups in script" do
      layout = [
        { "type" => "text", "text" => "Alpha", "bbox" => [0, 0, 10, 10], "font_size" => 12 }
      ]

      html = PdfPageHtmlRenderer.render(
        layout: layout,
        width: 100,
        height: 200,
        scale: 2,
        areas_to_show: { "x0" => 1, "y0" => 2, "x1" => 3, "y1" => 4, "extra" => "ignored" },
        items_to_remember: [[{ "id" => "el-1", "text" => "Alpha" }]],
        load_js: true
      )

      assert_includes html, '"x0":1'
      assert_includes html, '"y0":2'
      assert_includes html, "INITIAL_PICKED_TEXT_GROUPS"
      assert_includes html, "el-1"
      assert_includes html, "Alpha"
    end

    test "study mode hides authoring toolbar and embeds recall script" do
      layout = [
        { "type" => "text", "text" => "Alpha", "bbox" => [0, 0, 10, 10], "font_size" => 12 },
        { "type" => "text", "text" => "Beta", "bbox" => [20, 0, 30, 10], "font_size" => 12 }
      ]

      html = PdfPageHtmlRenderer.render(
        layout: layout,
        width: 100,
        height: 200,
        scale: 2,
        mode: :study,
        areas_to_show: { "x0" => 0, "y0" => 0, "x1" => 40, "y1" => 40 },
        items_to_remember: [[{ "id" => "el-1", "text" => "Alpha" }]],
        load_js: true
      )

      refute_includes html, "btn-pick-area"
      assert_includes html, "flash-card-study-viewport"
      assert_includes html, "flash-card-hidden-recall-item"
      assert_includes html, "flash-card-study-show-next-item"
      assert_includes html, "INITIAL_PICKED_TEXT_GROUPS"
      assert_includes html, '"x0":0'
    end

    test "study mode with areas_to_show wraps page in flash-card-study-viewport" do
      layout = [
        { "type" => "text", "text" => "Alpha", "bbox" => [0, 0, 10, 10], "font_size" => 12 }
      ]

      html = PdfPageHtmlRenderer.render(
        layout: layout,
        width: 100,
        height: 200,
        scale: 2,
        mode: :study,
        areas_to_show: { "x0" => 0, "y0" => 0, "x1" => 40, "y1" => 40 },
        items_to_remember: [[{ "id" => "el-1", "text" => "Alpha" }]],
        load_js: true
      )

      assert_includes html, "flash-card-study-viewport"
      assert_includes html, "width:80px"
      assert_includes html, "height:80px"
      assert_match(/left:\s*-?0(?:\.0+)?px/, html)
      assert_match(/top:\s*-?0(?:\.0+)?px/, html)
    end

    test "study viewport clamps bbox to layout bounds and offsets page" do
      layout = [
        { "type" => "text", "text" => "Z", "bbox" => [0, 0, 5, 5], "font_size" => 12 }
      ]

      html = PdfPageHtmlRenderer.render(
        layout: layout,
        width: 100,
        height: 200,
        scale: 1,
        mode: :study,
        areas_to_show: { "x0" => 10, "y0" => 10, "x1" => 500, "y1" => 500 },
        load_js: false
      )

      assert_includes html, "flash-card-study-viewport"
      assert_includes html, "width:90px"
      assert_includes html, "height:190px"
      assert_match(/left:\s*-10px/, html)
      assert_match(/top:\s*-10px/, html)
    end

    test "study mode without intersecting bbox omits viewport wrapper" do
      layout = [
        { "type" => "text", "text" => "Z", "bbox" => [0, 0, 5, 5], "font_size" => 12 }
      ]

      html = PdfPageHtmlRenderer.render(
        layout: layout,
        width: 100,
        height: 200,
        scale: 1,
        mode: :study,
        areas_to_show: { "x0" => 300, "y0" => 300, "x1" => 400, "y1" => 400 },
        load_js: false
      )

      refute_includes html, "flash-card-study-viewport"
    end

    test "renders vector path ids and initial transform metadata" do
      layout = [
        {
          "type" => "vector",
          "bbox" => [0, 0, 10, 10],
          "paths" => [
            { "d" => "M 0 0 L 9 9", "stroke" => "#111111", "stroke_width" => 1, "fill" => "none", "bbox" => [0, 0, 9, 9] }
          ]
        }
      ]

      html = PdfPageHtmlRenderer.render(
        layout: layout,
        width: 10,
        height: 10,
        scale: 1,
        load_js: true,
        mode: :authoring,
        items_to_remember: [],
        areas_to_show: {},
        vector_adjustments: [{ "path_id" => "vector-path-1", "dx" => 5, "dy" => -3 }]
      )

      assert_includes html, 'id="vector-path-1"'
      assert_includes html, 'data-dx="5"'
      assert_includes html, 'data-dy="-3"'
      assert_includes html, 'transform="translate(5, -3)"'
      assert_includes html, "INITIAL_VECTOR_ADJUSTMENTS"
    end

    test "renders text adjustments on text divs and embeds initial constant in script" do
      layout = [
        { "type" => "text", "text" => "Hi", "bbox" => [10, 20, 50, 35], "font_size" => 12 }
      ]

      html = PdfPageHtmlRenderer.render(
        layout: layout,
        width: 100,
        height: 200,
        scale: 2,
        load_js: true,
        mode: :authoring,
        items_to_remember: [],
        areas_to_show: {},
        text_adjustments: [{ "element_id" => "el-1", "dx" => 3, "dy" => -2 }]
      )

      assert_includes html, 'id="el-1"'
      assert_includes html, 'data-dx="3"'
      assert_includes html, 'data-dy="-2"'
      assert_includes html, "transform: translate(6px, -4px)"
      assert_includes html, "INITIAL_TEXT_ADJUSTMENTS"
    end

    test "study mode without areas_to_show omits viewport wrapper" do
      layout = [
        { "type" => "text", "text" => "Only", "bbox" => [0, 0, 10, 10], "font_size" => 12 }
      ]

      html = PdfPageHtmlRenderer.render(
        layout: layout,
        width: 100,
        height: 200,
        scale: 2,
        mode: :study,
        areas_to_show: {},
        items_to_remember: [[{ "id" => "el-1", "text" => "Only" }]],
        load_js: false
      )

      refute_includes html, "flash-card-study-viewport"
    end
  end
end
