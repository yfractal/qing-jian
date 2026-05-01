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
        self.assertIn("function collectTextTargetsForPick(e)", js)
        self.assertIn("window.getSelection ? window.getSelection() : null", js)
        self.assertIn("range.intersectsNode(el)", js)
        self.assertIn("document.elementsFromPoint(e.clientX, e.clientY)", js)
        self.assertIn("const targets = collectTextTargetsForPick(e);", js)
        self.assertIn("targets.forEach((target) => {", js)
        self.assertIn("syncRememberedHighlights();", js)

    def test_js_logs_grouped_picked_text_items(self):
        js = build_selection_js(1.5)
        self.assertIn("const pickedTextItems = [];", js)
        self.assertIn("let currentPickedTextItem = [];", js)
        self.assertIn("function startNewPickedTextItem()", js)
        self.assertIn('console.log("Picked text items:", items);', js)
        self.assertIn('type: "picked-text-items-updated",', js)
        self.assertIn("items: items", js)
        self.assertIn("window.parent.postMessage(", js)
        self.assertIn("id: target.id,", js)
        self.assertIn("text: text", js)


if __name__ == "__main__":
    unittest.main()
