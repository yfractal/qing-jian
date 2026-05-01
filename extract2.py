import fitz
import os
import html


def extract_layout(pdf_path, page_number):
    doc = fitz.open(pdf_path)
    page = doc[page_number]

    layout = []

    data = page.get_text("dict")

    # ------------------------
    # TEXT (line-based)
    # ------------------------
    for block in data["blocks"]:
        if block["type"] != 0:
            continue

        for line in block["lines"]:
            spans = line["spans"]

            if not spans:
                continue

            # Merge spans into one line
            text = "".join(span["text"] for span in spans).strip()
            if not text:
                continue

            x0, y0, x1, y1 = line["bbox"]

            # estimate font size
            font_size = max(span["size"] for span in spans)

            layout.append({
                "type": "text",
                "text": text,
                "bbox": [x0, y0, x1, y1],
                "font_size": font_size
            })

    # ------------------------
    # IMAGES
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

        filename = f"img_{page_number}_{img_index}.{ext}"
        os.makedirs("output", exist_ok=True)
        filepath = os.path.join("output", filename)

        with open(filepath, "wb") as f:
            f.write(image_bytes)

        layout.append({
            "type": "image",
            "file": filepath,
            "bbox": [x0, y0, x1, y1]
        })

        img_index += 1

    return layout, page.rect.width, page.rect.height


# ------------------------
# HTML RENDERER
# ------------------------

def render_html(layout, width, height, out_file="page.html", scale=1.5):
    def s(v): return v * scale

    html_parts = []

    html_parts.append(f"""
    <html>
    <head>
    <meta charset="utf-8">
    <style>
        body {{
            background:#eee;
        }}
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
            transform-origin: left top;
        }}
        .image {{
            position:absolute;
        }}
    </style>
    </head>
    <body>
    <div class="page">
    """)

    # Sort for correct layering (top → bottom)
    layout.sort(key=lambda x: (x["bbox"][1], x["bbox"][0]))

    for el in layout:
        x0, y0, x1, y1 = el["bbox"]

        if el["type"] == "text":
            text = html.escape(el["text"])
            font_size = el["font_size"] * scale * 0.9

            html_parts.append(f"""
            <div class="text"
                style="
                    left:{s(x0)}px;
                    top:{s(y0)}px;
                    font-size:{font_size}px;
                ">
                {text}
            </div>
            """)

        elif el["type"] == "image":
            w = s(x1 - x0)
            h = s(y1 - y0)

            html_parts.append(f"""
            <img class="image"
                src="{el['file']}"
                style="
                    left:{s(x0)}px;
                    top:{s(y0)}px;
                    width:{w}px;
                    height:{h}px;
                ">
            """)

    html_parts.append("""
    </div>
    </body>
    </html>
    """)

    with open(out_file, "w", encoding="utf-8") as f:
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
