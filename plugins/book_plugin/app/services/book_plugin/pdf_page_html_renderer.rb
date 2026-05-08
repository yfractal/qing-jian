# frozen_string_literal: true

require "erb"
require_relative "pdf_selection_script"
require_relative "pdf_flash_card_study_script"

module BookPlugin
  class PdfPageHtmlRenderer
    class << self
      def render(layout:, width:, height:, scale: 1.5, area: nil, load_js: true,
                 mode: :authoring, areas_to_show: nil, items_to_remember: nil, vector_adjustments: nil)
        new(
          layout: layout,
          width: width,
          height: height,
          scale: scale,
          area: area,
          load_js: load_js,
          mode: mode,
          areas_to_show: areas_to_show,
          items_to_remember: items_to_remember,
          vector_adjustments: vector_adjustments
        ).render
      end
    end

    # PDFs often encode page graphics as white ink for dark backgrounds; on our white
    # `.page` they disappear unless remapped to a dark paint.
    VECTOR_PAINT_NONE = %w[none transparent].freeze
    VECTOR_BLACK = "#000000"

    def initialize(layout:, width:, height:, scale:, area:, load_js: true,
                   mode: :authoring, areas_to_show: nil, items_to_remember: nil, vector_adjustments: nil)
      @layout = layout
      @width = width.to_f
      @height = height.to_f
      @scale = scale.to_f
      @area = area
      @load_js = load_js
      @mode = mode.to_sym
      @areas_to_show = areas_to_show || {}
      @items_to_remember = items_to_remember
      @vector_adjustments_list = normalize_vector_adjustments_param(vector_adjustments)
      @vector_adjustments_by_path_id = @vector_adjustments_list.index_by { |h| h["path_id"] }
    end

    def render
      @study_viewport = build_study_viewport_clip
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

    def normalize_vector_adjustments_param(raw)
      list =
        case raw
        when nil then []
        when Array then raw
        else []
        end

      list.filter_map do |entry|
        next unless entry.is_a?(Hash)

        path_id = (entry["path_id"] || entry[:path_id]).to_s
        next if path_id.empty?

        {
          "path_id" => path_id,
          "dx" => entry["dx"].to_f,
          "dy" => entry["dy"].to_f
        }
      end
    end

    def resolved_initial_area_pdf
      return @area if @area.present?

      h = @areas_to_show.stringify_keys
      return nil unless %w[x0 y0 x1 y1].all? { |k| h.key?(k) }

      h.slice("x0", "y0", "x1", "y1").transform_values(&:to_f)
    end

    def build_study_viewport_clip
      return nil unless @mode == :study

      area = resolved_initial_area_pdf
      return nil if area.blank?

      ax0 = area["x0"].to_f
      ay0 = area["y0"].to_f
      ax1 = area["x1"].to_f
      ay1 = area["y1"].to_f

      x_lo, x_hi = [ax0, ax1].minmax
      y_lo, y_hi = [ay0, ay1].minmax

      ix0 = [x_lo, 0.0].max
      iy0 = [y_lo, 0.0].max
      ix1 = [x_hi, @width].min
      iy1 = [y_hi, @height].min

      return nil if ix1 <= ix0 || iy1 <= iy0

      {
        ix0: ix0,
        iy0: iy0,
        vw: (ix1 - ix0) * @scale,
        vh: (iy1 - iy0) * @scale,
        ox: -ix0 * @scale,
        oy: -iy0 * @scale
      }
    end

    def css_px(value)
      f = value.to_f
      i = f.to_i
      return i.to_s if (f - i).abs < 1e-6

      s = format("%.4f", f)
      s.sub(/0+\z/, "").sub(/\.\z/, "")
    end

    def picked_text_groups_for_script
      items = @items_to_remember
      return nil if items.blank?

      if items.is_a?(Array) && items.all? { |e| e.is_a?(String) }
        return items
      end

      if items.is_a?(Array) && items.first.is_a?(Array)
        return items
      end

      if items.is_a?(Array) && items.all? { |e| e.is_a?(Hash) }
        return [items]
      end

      nil
    end

    def header_css(s)
      w = s.call(@width)
      h = s.call(@height)
      body_class = @study_viewport ? ' class="flash-card-study-clipped"' : ""
      study_viewport_css = if @study_viewport
        vp = @study_viewport
        <<~CSS

        body.flash-card-study-clipped { margin: 0; }

        .flash-card-study-viewport .page {
            margin: 0;
            left: #{css_px(vp[:ox])}px;
            top: #{css_px(vp[:oy])}px;
        }
        CSS
      else
        ""
      end

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
            pointer-events:auto;
        }

        .vector-layer path {
            cursor: move;
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

        .flash-card-hidden-recall-item {
            color: transparent !important;
            text-shadow: none !important;
            background: rgba(31, 41, 55, 0.16);
            border-radius: 4px;
        }

        .flash-card-next-recall-item {
            outline: 2px solid #f59e0b;
            background: rgba(245, 158, 11, 0.22);
        }

        .flash-card-revealed-recall-item {
            background: rgba(34, 197, 94, 0.22);
            border-radius: 4px;
        }
        #{study_viewport_css}
        </style>
        </head>
        <body#{body_class}>
      HTML
    end

    def toolbar_and_page_open
      if @mode == :study
        if @study_viewport
          vp = @study_viewport
          return <<~HTML
            <div class="flash-card-study-viewport" style="overflow:hidden;width:#{css_px(vp[:vw])}px;height:#{css_px(vp[:vh])}px;margin:0 auto;">
            <div class="page">
          HTML
        end

        return '<div class="page">'
      end

      initial_area = resolved_initial_area_pdf
      text_btn_class = initial_area.nil? ? ' class="is-active"' : ""
      area_btn_class = initial_area.present? ? ' class="is-active"' : ""
      <<~HTML
        <div class="toolbar">
            <button id="btn-pick-text" type="button"#{text_btn_class}>Pick items to remember</button>
            <button id="btn-pick-area" type="button"#{area_btn_class}>Pick area to show</button>
            <button id="btn-drag-vectors" type="button">Drag vectors</button>
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

      vector_paths.each_with_index do |path, index|
        path_id = "vector-path-#{index + 1}"
        d = ERB::Util.html_escape(path.fetch("d"))
        stroke = ERB::Util.html_escape(vector_paint_for_display(path.fetch("stroke", "none")))
        fill = ERB::Util.html_escape(vector_paint_for_display(path.fetch("fill", "none")))
        stroke_width = path.fetch("stroke_width", 1)
        px0, py0, px1, py1 = path.fetch("bbox")
        adj = @vector_adjustments_by_path_id[path_id] || { "dx" => 0.0, "dy" => 0.0 }
        dx = fmt_num(adj["dx"])
        dy = fmt_num(adj["dy"])
        lines << <<~HTML
          <path id="#{path_id}"
                d="#{d}"
                stroke="#{stroke}"
                stroke-width="#{stroke_width}"
                fill="#{fill}"
                data-dx="#{dx}"
                data-dy="#{dy}"
                data-x0="#{fmt_num(px0)}"
                data-y0="#{fmt_num(py0)}"
                data-x1="#{fmt_num(px1)}"
                data-y1="#{fmt_num(py1)}"
                transform="translate(#{dx}, #{dy})" />
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
      viewport_close = @study_viewport ? "</div>\n" : ""
      <<~HTML
        <div id="selection-box"></div>
        </div>
        #{viewport_close}
      HTML
    end

    def document_close
      chunks = []
      if @load_js
        script_builder = @mode == :study ? PdfFlashCardStudyScript : PdfSelectionScript
        js = script_builder.build(
          scale: @scale,
          initial_area: resolved_initial_area_pdf,
          initial_picked_text_groups: picked_text_groups_for_script,
          initial_vector_adjustments: @vector_adjustments_list
        )
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
