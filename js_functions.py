import json
from pathlib import Path


SELECTION_JS_PATH = (
    Path(__file__).resolve().parent
    / "plugins"
    / "book_plugin"
    / "app"
    / "assets"
    / "javascripts"
    / "book_plugin"
    / "flash_card_selection.js"
)
SELECTION_JS_SOURCE = SELECTION_JS_PATH.read_text(encoding="utf-8")


def build_selection_js(scale, initial_area=None):
    config = {
        "scale": scale,
        "initialAreaPdf": initial_area if initial_area else None,
    }
    config_assignment = f"window.__BOOK_PLUGIN_SELECTION_CONFIG__ = {json.dumps(config)};"
    return f"{config_assignment}\n{SELECTION_JS_SOURCE}"
