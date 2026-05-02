#!/usr/bin/env ruby
# frozen_string_literal: true

# Writes pdf_selection_script.js.txt from Python js_functions.build_selection_js.
# Run from repo root: ruby tools/generate_pdf_selection_script_literal.rb

require "open3"
require "pathname"

ROOT = Pathname.new(__dir__).join("..").expand_path
OUT_JS = ROOT.join(
  "plugins/book_plugin/app/services/book_plugin/pdf_selection_script.js"
)

cmd = [
  "python3", "-c",
  <<~PY
    import sys
    sys.path.insert(0, #{ROOT.to_s.inspect})
    from js_functions import build_selection_js
    text = build_selection_js(1.0, None)
    sys.stdout.write(text)
  PY
]

stdout, stderr, status = Open3.capture3(*cmd)
unless status.success?
  warn stderr
  abort "python failed: #{status.inspect}"
end

body = stdout
abort "empty JS from python" if body.strip.empty?

unless body.include?("const SCALE = 1.0;")
  abort "expected placeholder scale 1.0 in script; update generator if js_functions changed"
end
unless body.include?("const INITIAL_AREA_PDF = null;")
  abort "expected INITIAL_AREA_PDF = null; update generator if js_functions changed"
end

OUT_JS.parent.mkpath
OUT_JS.write(body, encoding: Encoding::UTF_8)

puts "Wrote #{OUT_JS}"
