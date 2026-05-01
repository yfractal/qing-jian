import unittest

from js_functions import build_selection_js


class BuildSelectionJsHighlightTests(unittest.TestCase):
    def test_js_declares_highlight_sync_helper(self):
        js = build_selection_js(1.5)
        self.assertIn("function syncRememberedHighlights()", js)
        self.assertIn('document.querySelectorAll(".text.remembered").forEach((el) => {', js)

    def test_js_reapplies_highlights_after_toggle(self):
        js = build_selection_js(1.5)
        self.assertIn("rememberedTextIds.delete(target.id);", js)
        self.assertIn("rememberedTextIds.add(target.id);", js)
        self.assertIn("syncRememberedHighlights();", js)

    def test_js_derives_picked_texts_from_remembered_ids(self):
        js = build_selection_js(1.5)
        self.assertIn("const pickedTexts = Array.from(rememberedTextIds)", js)
        self.assertIn(".map((id) => document.getElementById(id))", js)
        self.assertIn('console.log("Picked text items:", pickedTexts);', js)


if __name__ == "__main__":
    unittest.main()
