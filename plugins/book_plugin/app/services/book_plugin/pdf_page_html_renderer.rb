# frozen_string_literal: true

require "base64"
require "erb"
require "securerandom"
require_relative "pdf_selection_script"

module BookPlugin
  class PdfPageHtmlRenderer
    class << self
      def render(layout:, width:, height:, scale: 1.5, area: nil)
        new(layout: layout, width: width, height: height, scale: scale, area: area).render
      end
    end

    def initialize(layout:, width:, height:, scale:, area:)
      @layout = layout
      @width = width.to_f
      @height = height.to_f
      @scale = scale.to_f
      @area = area
    end

    def render
      parts = []
      s = ->(v) { v * @scale }

      parts << header_css(s)
      parts << toolbar_and_page_open

      sorted = @layout.sort_by { |el| [el.fetch("bbox")[1], el.fetch("bbox")[0]] }
      vector_paths = []

      sorted.each do |el|
        x0, y0, x1, y1 = el.fetch("bbox")
        case el["type"]
        when "text"
          parts << text_div(el, x0, y0, s)
        when "image"
          parts << image_tag(el, x0, y0, x1, y1, s)
        when "vector"
          vector_paths.concat(el["paths"] || [])
        end
      end

      parts << svg_block(vector_paths) if vector_paths.any?
      parts << selection_box_close
      parts << script_footer
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
      <<~HTML
        <div class="toolbar">
            <button id="btn-pick-area" type="button">Pick area to show</button>
            <button id="btn-pick-text" type="button">Pick items to remember</button>
        </div>
        <div class="page">
      HTML
    end

    def text_div(el, x0, y0, s)
      element_id = "el-#{SecureRandom.hex(16)}"
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

    def image_tag(el, x0, y0, x1, y1, s)
      element_id = "el-#{SecureRandom.hex(16)}"
      path = el.fetch("file")
      src = image_data_uri(path)
      src_escaped = ERB::Util.html_escape(src)
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

    def image_data_uri(path)
      bytes = File.binread(path)
      ext = File.extname(path).delete(".").downcase
      mime =
        case ext
        when "jpg", "jpeg" then "image/jpeg"
        when "png" then "image/png"
        when "webp" then "image/webp"
        else "application/octet-stream"
        end
      "data:#{mime};base64,#{Base64.strict_encode64(bytes)}"
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
        stroke = ERB::Util.html_escape(path.fetch("stroke", "none"))
        fill = ERB::Util.html_escape(path.fetch("fill", "none"))
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

    def script_footer
      js = PdfSelectionScript.build(scale: @scale, initial_area: @area)
      <<~HTML
        <script>
        #{js}
        </script>
        </body>
        </html>
      HTML
    end
  end
end
