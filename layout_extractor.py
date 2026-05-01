import fitz
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
        commands.extend(f"L {fmt_num(x)} {fmt_num(y)}" for x, y in coords[1:])
        commands.append("Z")
        return " ".join(commands)

    return None


def path_bbox_for_item(item):
    operator = item[0]
    points = []

    if operator == "l":
        points = [point_xy(item[1]), point_xy(item[2])]
    elif operator == "c":
        points = [
            point_xy(item[1]),
            point_xy(item[2]),
            point_xy(item[3]),
            point_xy(item[4]),
        ]
    elif operator == "re":
        x0, y0, x1, y1 = rect_xy(item[1])
        points = [(x0, y0), (x1, y1)]
    elif operator == "qu":
        quad = item[1]
        points = [
            point_xy(quad.ul),
            point_xy(quad.ur),
            point_xy(quad.lr),
            point_xy(quad.ll),
        ]
    else:
        return None

    xs = [p[0] for p in points]
    ys = [p[1] for p in points]
    return [min(xs), min(ys), max(xs), max(ys)]


def drawing_to_svg_paths(drawing):
    stroke = color_to_css(drawing.get("color"))
    fill = color_to_css(drawing.get("fill"))
    stroke_width = drawing.get("width") or 1

    paths = []
    for item in drawing.get("items", []):
        path_d = path_d_for_item(item)
        path_bbox = path_bbox_for_item(item)
        if not path_d or not path_bbox:
            continue

        paths.append(
            {
                "d": path_d,
                "stroke": stroke,
                "stroke_width": stroke_width,
                "fill": fill,
                "bbox": path_bbox,
            }
        )

    return paths


def extract_layout(pdf_path, page_number, output_dir="output"):
    doc = fitz.open(pdf_path)
    page = doc[page_number]

    layout = []
    data = page.get_text("dict")

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

            layout.append(
                {
                    "type": "text",
                    "text": text,
                    "bbox": [x0, y0, x1, y1],
                    "font_size": font_size,
                }
            )

    img_index = 0
    os.makedirs(output_dir, exist_ok=True)
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
        path = os.path.join(output_dir, filename)

        with open(path, "wb") as f:
            f.write(image_bytes)

        layout.append({"type": "image", "file": path, "bbox": [x0, y0, x1, y1]})
        img_index += 1

    for drawing in page.get_drawings():
        rect = drawing.get("rect")
        paths = drawing_to_svg_paths(drawing)
        if not rect or not paths:
            continue

        x0, y0, x1, y1 = rect
        layout.append({"type": "vector", "bbox": [x0, y0, x1, y1], "paths": paths})

    return layout, page.rect.width, page.rect.height
