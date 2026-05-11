import json
from pathlib import Path


_SELECTION_JS_REL = (
    Path("plugins")
    / "book_plugin"
    / "app"
    / "services"
    / "book_plugin"
    / "pdf_selection_script.js"
)


def build_selection_js(
    scale,
    initial_area=None,
    initial_picked_text_groups=None,
    initial_vector_adjustments=None,
    initial_text_adjustments=None,
):
    """Mirror PdfSelectionScript.build for parity tests (reads canonical JS template)."""
    path = Path(__file__).resolve().parent / _SELECTION_JS_REL
    body = path.read_text(encoding="utf-8")
    compact = (",", ":")
    initial_json = (
        json.dumps(initial_area, separators=compact) if initial_area is not None else "null"
    )
    groups_json = (
        json.dumps(initial_picked_text_groups, separators=compact)
        if initial_picked_text_groups is not None
        else "null"
    )
    vector_json = json.dumps(initial_vector_adjustments or [], separators=compact)
    text_adj_json = json.dumps(initial_text_adjustments or [], separators=compact)
    body = body.replace("const SCALE = 1.0;", f"const SCALE = {float(scale)};")
    body = body.replace(
        "const INITIAL_AREA_PDF = null;",
        f"const INITIAL_AREA_PDF = {initial_json};",
    )
    body = body.replace(
        "const INITIAL_PICKED_TEXT_GROUPS = null;",
        f"const INITIAL_PICKED_TEXT_GROUPS = {groups_json};",
    )
    body = body.replace(
        "const INITIAL_VECTOR_ADJUSTMENTS = [];",
        f"const INITIAL_VECTOR_ADJUSTMENTS = {vector_json};",
    )
    body = body.replace(
        "const INITIAL_TEXT_ADJUSTMENTS = [];",
        f"const INITIAL_TEXT_ADJUSTMENTS = {text_adj_json};",
    )
    return body
