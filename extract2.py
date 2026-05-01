import fitz
import os


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
    # VECTORS (cleaned)
    # ------------------------
    raw_rects = []

    for d in page.get_drawings():
        rect = d.get("rect")
        if not rect:
            continue

        x0, y0, x1, y1 = rect

        w = x1 - x0
        h = y1 - y0

        # filter tiny noise
        if w < 5 or h < 5:
            continue

        raw_rects.append([x0, y0, x1, y1])

    merged_rects = merge_rects(raw_rects)

    for r in merged_rects:
        x0, y0, x1, y1 = r

        layout.append({
            "type": "vector",
            "bbox": [x0, y0, x1, y1]
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

        .vector {{
            position:absolute;
            border: 1px solid rgba(255,0,0,0.4);
            z-index: 2;
            pointer-events:none;
        }}
    </style>
    </head>
    <body>
    <div class="page">
    """)

    layout.sort(key=lambda x: (x["bbox"][1], x["bbox"][0]))

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
            html_parts.append(f"""
            <img class="image"
                src="{el['file']}"
                style="
                    left:{s(x0)}px;
                    top:{s(y0)}px;
                    width:{s(x1-x0)}px;
                    height:{s(y1-y0)}px;
                ">
            """)

        elif el["type"] == "vector":
            html_parts.append(f"""
            <div class="vector"
                style="
                    left:{s(x0)}px;
                    top:{s(y0)}px;
                    width:{s(x1-x0)}px;
                    height:{s(y1-y0)}px;
                ">
            </div>
            """)

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
