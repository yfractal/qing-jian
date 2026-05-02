import sys
import tempfile
import types
import unittest
from pathlib import Path


sys.modules.setdefault("fitz", types.SimpleNamespace())

import extract2


class Extract2RenderHtmlLoadJsTest(unittest.TestCase):
    def setUp(self):
        self.layout = [
            {
                "type": "text",
                "bbox": [10, 20, 80, 30],
                "text": "hello",
                "font_size": 12,
            }
        ]

    def test_render_html_includes_script_by_default(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            out_file = Path(tmpdir) / "page.html"
            extract2.render_html(self.layout, 100, 100, out_file=str(out_file), scale=1)
            html = out_file.read_text()

        self.assertIn("<script>", html)
        self.assertIn("window.__BOOK_PLUGIN_SELECTION_CONFIG__", html)

    def test_render_html_includes_script_when_load_js_enabled(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            out_file = Path(tmpdir) / "page.html"
            extract2.render_html(
                self.layout,
                100,
                100,
                out_file=str(out_file),
                scale=1,
                load_js=True,
            )
            html = out_file.read_text()

        self.assertIn("<script>", html)
        self.assertIn("window.__BOOK_PLUGIN_SELECTION_CONFIG__", html)

    def test_render_html_excludes_script_when_load_js_disabled(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            out_file = Path(tmpdir) / "page.html"
            extract2.render_html(
                self.layout,
                100,
                100,
                out_file=str(out_file),
                scale=1,
                load_js=False,
            )
            html = out_file.read_text()

        self.assertNotIn("<script>", html)
        self.assertNotIn("window.__BOOK_PLUGIN_SELECTION_CONFIG__", html)


if __name__ == "__main__":
    unittest.main()
