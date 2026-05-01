import fitz
import html
import os


def fmt_num(value):
    value = float(value)
    if value.is_integer():
        return str(int(value))
    return f"{value:.4f}".rstrip("0").rstrip(".")


def point_xy(point):
    if hasattr(point, "x") and hasattr(point, "y"):
        return point.x, point.y
    return point[0], point[1]


def rect_xy(rect):
    if all(hasattr(rect, attr) for attr in ("x0", "y0", "x1", "y1")):
        return rect.x0, rect.y0, rect.x1, rect.y1
    return rect[0], rect[1], rect[2], rect[3]


def color_to_css(color, default="none"):
    if color is None:
        return default

    values = []
    for component in color[:3]:
        component = float(component)
        if component <= 1:
            component *= 255
        values.append(max(0, min(255, round(component))))

    return f"rgb({values[0]}, {values[1]}, {values[2]})"


def path_d_for_item(item):
    operator = item[0]

    if operator == "l":
        x0, y0 = point_xy(item[1])
        x1, y1 = point_xy(item[2])
        return f"M {fmt_num(x0)} {fmt_num(y0)} L {fmt_num(x1)} {fmt_num(y1)}"

    if operator == "c":
        x0, y0 = point_xy(item[1])
        x1, y1 = point_xy(item[2])
        x2, y2 = point_xy(item[3])
        x3, y3 = point_xy(item[4])
        return (
            f"M {fmt_num(x0)} {fmt_num(y0)} "
            f"C {fmt_num(x1)} {fmt_num(y1)} "
            f"{fmt_num(x2)} {fmt_num(y2)} "
            f"{fmt_num(x3)} {fmt_num(y3)}"
        )

    if operator == "re":
        x0, y0, x1, y1 = rect_xy(item[1])
        return (
            f"M {fmt_num(x0)} {fmt_num(y0)} "
            f"L {fmt_num(x1)} {fmt_num(y0)} "
            f"L {fmt_num(x1)} {fmt_num(y1)} "
            f"L {fmt_num(x0)} {fmt_num(y1)} Z"
        )

    if operator == "qu":
        quad = item[1]
        points = [quad.ul, quad.ur, quad.lr, quad.ll]
        coords = [point_xy(point) for point in points]
        x0, y0 = coords[0]
        commands = [f"M {fmt_num(x0)} {fmt_num(y0)}"]
        commands.extend(
            f"L {fmt_num(x)} {fmt_num(y)}"
            for x, y in coords[1:]
        )
        commands.append("Z")
        return " ".join(commands)

    return None


def drawing_to_svg_paths(drawing):
    stroke = color_to_css(drawing.get("color"))
    fill = color_to_css(drawing.get("fill"))
    stroke_width = drawing.get("width") or 1

    paths = []
    for item in drawing.get("items", []):
        path_d = path_d_for_item(item)
        if not path_d:
            continue

        paths.append({
            "d": path_d,
            "stroke": stroke,
            "stroke_width": stroke_width,
            "fill": fill,
        })

    return paths


def merge_rects(rects, threshold=5):
    merged = []

    for r in rects:
        rx0, ry0, rx1, ry1 = r
        merged_flag = False

        for i, m in enumerate(merged):
            mx0, my0, mx1, my1 = m

            # overlap / near check
            if not (rx1 < mx0 - threshold or rx0 > mx1 + threshold or
                    ry1 < my0 - threshold or ry0 > my1 + threshold):

                merged[i] = [
                    min(mx0, rx0),
                    min(my0, ry0),
                    max(mx1, rx1),
                    max(my1, ry1)
                ]
                merged_flag = True
                break

        if not merged_flag:
            merged.append(list(r))

    return merged


def extract_layout(pdf_path, page_number):
    doc = fitz.open(pdf_path)
    page = doc[page_number]

    layout = []
    data = page.get_text("dict")

    # ------------------------
    # TEXT (same as before)
    # ------------------------
    for block in data["blocks"]:
        if block["type"] != 0:
            continue

        for line in block["lines"]:
            spans = line["spans"]
            if not spans:
                continue

            text = "".join(s["text"] for s in spans).strip()
            if not text:
                continue

            x0, y0, x1, y1 = line["bbox"]
            font_size = max(s["size"] for s in spans)

            layout.append({
                "type": "text",
                "text": text,
                "bbox": [x0, y0, x1, y1],
                "font_size": font_size
            })

    # ------------------------
    # IMAGES (same)
    # ------------------------
    img_index = 0
    for block in data["blocks"]:
        if block["type"] != 1:
            continue

        x0, y0, x1, y1 = block["bbox"]

        if "xref" in block:
            base_image = doc.extract_image(block["xref"])
            image_bytes = base_image["image"]
            ext = base_image["ext"]
        elif "image" in block:
            image_bytes = block["image"]
            ext = "png"
        else:
            continue

        os.makedirs("output", exist_ok=True)
        filename = f"img_{page_number}_{img_index}.{ext}"
        path = os.path.join("output", filename)

        with open(path, "wb") as f:
            f.write(image_bytes)

        layout.append({
            "type": "image",
            "file": path,
            "bbox": [x0, y0, x1, y1]
        })

        img_index += 1

    # ------------------------
    # VECTORS
    # ------------------------
    for d in page.get_drawings():
        rect = d.get("rect")
        paths = drawing_to_svg_paths(d)
        if not rect or not paths:
            continue

        x0, y0, x1, y1 = rect

        layout.append({
            "type": "vector",
            "bbox": [x0, y0, x1, y1],
            "paths": paths,
        })

    return layout, page.rect.width, page.rect.height


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
            overflow: visible;
        }}
    </style>
    </head>
    <body>
    <div class="page">
    """)

    layout.sort(key=lambda x: (x["bbox"][1], x["bbox"][0]))
    vector_paths = []

    for el in layout:
        x0, y0, x1, y1 = el["bbox"]

        if el["type"] == "text":
            html_parts.append(f"""
            <div class="text"
                style="
                    left:{s(x0)}px;
                    top:{s(y0)}px;
                    font-size:{el['font_size'] * scale * 0.9}px;
                ">
                {el['text']}
            </div>
            """)

        elif el["type"] == "image":
            src = html.escape(el["file"], quote=True)
            html_parts.append(f"""
            <img class="image"
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
            html_parts.append(f"""
                <path d="{d}"
                      stroke="{stroke}"
                      stroke-width="{stroke_width}"
                      fill="{fill}" />
            """)

        html_parts.append("</svg>")

    html_parts.append("</div></body></html>")

    with open(out_file, "w") as f:
        f.write("\n".join(html_parts))

    print(f"Saved → {out_file}")
# ------------------------
# MAIN
# ------------------------

if __name__ == "__main__":
    pdf_path = "/Users/y/Downloads/stretching-anatomy.pdf"
    page_number = 15

    layout, w, h = extract_layout(pdf_path, page_number)
    render_html(layout, w, h)
