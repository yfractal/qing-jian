import argparse
import html
import uuid

from js_functions import build_selection_js
from layout_extractor import extract_layout, fmt_num


def render_html(layout, width, height, out_file="page.html", scale=1.5):
    def s(v): return v * scale

    html_parts = []

    html_parts.append(f"""
<html>
<head>
<meta charset="utf-8">
<style>
body {{ background:#eee; }}

.page {{
    position: relative;
    width:{s(width)}px;
    height:{s(height)}px;
    margin:20px auto;
    background:white;
}}

.text {{
    position:absolute;
    white-space:nowrap;
    z-index: 3;
}}

.image {{
    position:absolute;
    z-index: 1;
}}

.vector-layer {{
    position:absolute;
    left: 0;
    top: 0;
    width: 100%;
    height: 100%;
    z-index: 2;
    pointer-events:none;
}}

#selection-box {{
    position: absolute;
    border: 2px dashed #007bff;
    background: rgba(0, 123, 255, 0.15);
    display: none;
    pointer-events: none;
    z-index: 10;
}}

.hidden {{
    display: none !important;
}}
</style>
</head>
<body>
<div class="page">
""")

    layout.sort(key=lambda x: (x["bbox"][1], x["bbox"][0]))
    vector_paths = []

    # ------------------------
    # TEXT + IMAGE
    # ------------------------
    for el in layout:
        x0, y0, x1, y1 = el["bbox"]

        if el["type"] == "text":
            element_id = f"el-{uuid.uuid4().hex}"
            text = html.escape(el["text"])

            html_parts.append(f"""
<div class="text"
    id="{element_id}"
    category="text"
    style="
        left:{s(x0)}px;
        top:{s(y0)}px;
        font-size:{el['font_size'] * scale * 0.9}px;
    ">
    {text}
</div>
""")

        elif el["type"] == "image":
            element_id = f"el-{uuid.uuid4().hex}"
            src = html.escape(el["file"], quote=True)

            html_parts.append(f"""
<img class="image"
    id="{element_id}"
    category="image"
    src="{src}"
    style="
        left:{s(x0)}px;
        top:{s(y0)}px;
        width:{s(x1-x0)}px;
        height:{s(y1-y0)}px;
    ">
""")

        elif el["type"] == "vector":
            vector_paths.extend(el.get("paths", []))

    # ------------------------
    # SVG
    # ------------------------
    if vector_paths:
        html_parts.append(f"""
<svg class="vector-layer"
     viewBox="0 0 {width} {height}"
     preserveAspectRatio="none">
""")

        for path in vector_paths:
            d = html.escape(path["d"], quote=True)
            stroke = html.escape(path.get("stroke", "none"), quote=True)
            fill = html.escape(path.get("fill", "none"), quote=True)
            stroke_width = path.get("stroke_width", 1)
            x0, y0, x1, y1 = path["bbox"]

            html_parts.append(f"""
<path d="{d}"
      stroke="{stroke}"
      stroke-width="{stroke_width}"
      fill="{fill}"
      data-x0="{fmt_num(x0)}"
      data-y0="{fmt_num(y0)}"
      data-x1="{fmt_num(x1)}"
      data-y1="{fmt_num(y1)}" />
""")

        html_parts.append("</svg>")

    # ------------------------
    # SELECTION BOX
    # ------------------------
    html_parts.append("""
<div id="selection-box"></div>
</div>
""")

    html_parts.append(f"""
<script>
{build_selection_js(scale)}
</script>
</body>
</html>
""")

    with open(out_file, "w", encoding="utf-8") as f:
        f.write("\n".join(html_parts))

    print(f"Saved → {out_file}")

def parse_args():
    parser = argparse.ArgumentParser(description="Extract PDF layout and render HTML.")
    parser.add_argument("pdf_path", help="Path to source PDF")
    parser.add_argument("--page", type=int, default=15, help="Zero-based page index")
    parser.add_argument("--out", default="page.html", help="Output HTML path")
    parser.add_argument("--scale", type=float, default=1.5, help="Render scale")
    parser.add_argument(
        "--output-dir",
        default="output",
        help="Directory to store extracted images",
    )
    return parser.parse_args()


if __name__ == "__main__":
    args = parse_args()
    layout, width, height = extract_layout(args.pdf_path, args.page, args.output_dir)
    render_html(layout, width, height, out_file=args.out, scale=args.scale)
