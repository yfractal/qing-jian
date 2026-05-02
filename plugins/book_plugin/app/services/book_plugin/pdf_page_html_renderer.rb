# frozen_string_literal: true

require "erb"
require_relative "pdf_selection_script"

module BookPlugin
  class PdfPageHtmlRenderer
    class << self
      def render(layout:, width:, height:, scale: 1.5, area: nil, load_js: true)
        new(layout: layout, width: width, height: height, scale: scale, area: area, load_js: load_js).render
      end
    end

    # PDFs often encode page graphics as white ink for dark backgrounds; on our white
    # `.page` they disappear unless remapped to a dark paint.
    VECTOR_PAINT_NONE = %w[none transparent].freeze
    VECTOR_BLACK = "#000000"

    def initialize(layout:, width:, height:, scale:, area:, load_js: true)
      @layout = layout
      @width = width.to_f
      @height = height.to_f
      @scale = scale.to_f
      @area = area
      @load_js = load_js
    end

    def render
      parts = []
      s = ->(v) { v * @scale }

      parts << header_css(s)
      parts << toolbar_and_page_open

      sorted = @layout.sort_by { |el| [el.fetch("bbox")[1], el.fetch("bbox")[0]] }
      vector_paths = []

      sorted.each_with_index do |el, idx|
        x0, y0, x1, y1 = el.fetch("bbox")
        element_id = "el-#{idx + 1}"
        case el["type"]
        when "text"
          parts << text_div(el, x0, y0, s, element_id: element_id)
        when "image"
          parts << image_tag(el, x0, y0, x1, y1, s, element_id: element_id)
        when "vector"
          vector_paths.concat(el["paths"] || [])
        end
      end

      parts << svg_block(vector_paths) if vector_paths.any?
      parts << selection_box_close
      parts << document_close
      parts.join("\n")
    end

    private

    def header_css(s)
      w = s.call(@width)
      h = s.call(@height)
      <<~HTML
        <html>
        <head>
        <meta charset="utf-8">
        <style>
        body { background:#eee; }

        .toolbar {
            width:#{w}px;
            margin:20px auto 0 auto;
            display:flex;
            gap:10px;
        }

        .toolbar button {
            border:1px solid #c9d2dc;
            background:#f7fafc;
            color:#1f2933;
            border-radius:6px;
            padding:8px 12px;
            font-size:14px;
            cursor:pointer;
        }

        .toolbar button.is-active {
            background:#1f6feb;
            border-color:#1f6feb;
            color:#fff;
        }

        .page {
            position: relative;
            width:#{w}px;
            height:#{h}px;
            margin:20px auto;
            background:white;
        }

        .text {
            position:absolute;
            white-space:nowrap;
            z-index: 3;
        }

        .image {
            position:absolute;
            z-index: 1;
        }

        .vector-layer {
            position:absolute;
            left: 0;
            top: 0;
            width: 100%;
            height: 100%;
            z-index: 2;
            pointer-events:none;
        }

        #selection-box {
            position: absolute;
            border: 2px dashed #007bff;
            background: rgba(0, 123, 255, 0.15);
            display: none;
            pointer-events: none;
            z-index: 10;
        }

        .hidden {
            display: none !important;
        }

        .remembered {
            background: rgba(255, 208, 0, 0.45);
            outline: 1px solid rgba(255, 166, 0, 0.9);
        }
        </style>
        </head>
        <body>
      HTML
    end

    def toolbar_and_page_open
      text_btn_class = @area.nil? ? ' class="is-active"' : ""
      area_btn_class = @area.present? ? ' class="is-active"' : ""
      <<~HTML
        <div class="toolbar">
            <button id="btn-pick-text" type="button"#{text_btn_class}>Pick items to remember</button>
            <button id="btn-pick-area" type="button"#{area_btn_class}>Pick area to show</button>
        </div>
        <div class="page">
      HTML
    end

    def text_div(el, x0, y0, s, element_id:)
      text = ERB::Util.html_escape(el.fetch("text"))
      fs = el.fetch("font_size") * @scale * 0.9
      <<~HTML
        <div class="text"
            id="#{element_id}"
            category="text"
            style="
                left:#{s.call(x0)}px;
                top:#{s.call(y0)}px;
                font-size:#{fs}px;
            ">
            #{text}
        </div>
      HTML
    end

    def image_tag(el, x0, y0, x1, y1, s, element_id:)
      src_escaped = ERB::Util.html_escape(image_src(el))
      <<~HTML
        <img class="image"
            id="#{element_id}"
            category="image"
            src="#{src_escaped}"
            style="
                left:#{s.call(x0)}px;
                top:#{s.call(y0)}px;
                width:#{s.call(x1 - x0)}px;
                height:#{s.call(y1 - y0)}px;
            ">
      HTML
    end

    def image_src(el)
      blob_id = el["active_storage_blob_id"]
      if blob_id.present?
        blob = ActiveStorage::Blob.find(blob_id)
        return Rails.application.routes.url_helpers.rails_blob_path(blob, only_path: true)
      end

      el.fetch("file")
    end

    def svg_block(vector_paths)
      lines = []
      lines << <<~HTML
        <svg class="vector-layer"
             viewBox="0 0 #{@width} #{@height}"
             preserveAspectRatio="none">
      HTML

      vector_paths.each do |path|
        d = ERB::Util.html_escape(path.fetch("d"))
        stroke = ERB::Util.html_escape(vector_paint_for_display(path.fetch("stroke", "none")))
        fill = ERB::Util.html_escape(vector_paint_for_display(path.fetch("fill", "none")))
        stroke_width = path.fetch("stroke_width", 1)
        px0, py0, px1, py1 = path.fetch("bbox")
        lines << <<~HTML
          <path d="#{d}"
                stroke="#{stroke}"
                stroke-width="#{stroke_width}"
                fill="#{fill}"
                data-x0="#{fmt_num(px0)}"
                data-y0="#{fmt_num(py0)}"
                data-x1="#{fmt_num(px1)}"
                data-y1="#{fmt_num(py1)}" />
        HTML
      end
      lines << "</svg>"
      lines.join("\n")
    end

    def vector_paint_for_display(value)
      raw = value.to_s.strip
      return "none" if raw.empty? || VECTOR_PAINT_NONE.include?(raw.downcase)
      return VECTOR_BLACK if light_vector_paint?(raw)

      raw
    end

    def light_vector_paint?(raw)
      s = raw.downcase.gsub(/\s/, "")
      return true if s == "white"
      return true if %w[#fff #ffffff].include?(s)

      if (m = s.match(/\Argb\((\d+),(\d+),(\d+)\)\z/))
        return rgb_triplet_light?(m[1].to_i, m[2].to_i, m[3].to_i)
      end

      if (m = s.match(/\Argba\((\d+),(\d+),(\d+),([\d.]+)\)\z/))
        a = m[4].to_f
        return false if a <= 0.01

        return rgb_triplet_light?(m[1].to_i, m[2].to_i, m[3].to_i)
      end

      if (m = s.match(/\A#([0-9a-f]{3})\z/))
        return hex_channels_light?([m[1][0], m[1][1], m[1][2]].map { |c| (c + c).to_i(16) })
      end

      if (m = s.match(/\A#([0-9a-f]{6})\z/))
        h = m[1]
        return hex_channels_light?([h[0, 2], h[2, 2], h[4, 2]].map { |pair| pair.to_i(16) })
      end

      if (m = s.match(/\Ahsl\((\d+),(\d+)%,(\d+)%\)\z/))
        return m[3].to_i >= 95
      end

      false
    end

    def rgb_triplet_light?(r, g, b)
      r >= 245 && g >= 245 && b >= 245
    end

    def hex_channels_light?(channels)
      rgb_triplet_light?(*channels)
    end

    def fmt_num(value)
      f = value.to_f
      i = f.to_i
      return i.to_s if (f - i).abs < 1e-9

      s = format("%.4f", f)
      s = s.sub(/0+\z/, "")
      s.sub(/\.\z/, "")
    end

    def selection_box_close
      <<~HTML
        <div id="selection-box"></div>
        </div>
      HTML
    end

    def document_close
      chunks = []
      if @load_js
        js = PdfSelectionScript.build(scale: @scale, initial_area: @area)
        chunks << <<~HTML
          <script>
          #{js}
          </script>
        HTML
      end
      chunks << <<~HTML
        </body>
        </html>
      HTML
      chunks.join("\n")
    end
  end
end
