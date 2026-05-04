# Design: Book Remember Flash Card — iframe shows “area to show” only (viewport clip)

**Date:** 2026-05-04  
**Status:** Approved concept (viewport clip, goal A: less margin, no in-iframe scrolling)

## Problem

On Remember Flash Cards, the study `iframe` uses `srcdoc` from `BookHtml#rendered_html(..., mode: :study)`. The HTML uses the **full** layout width and height. The flash card’s `areas_to_show` bbox is passed into the study script as `INITIAL_AREA_PDF` to **filter** which elements are visible for recall, but the document still occupies the whole page, leaving empty margin and scrollable area inside the iframe.

## Goal

When a complete `areas_to_show` rectangle (`x0`, `y0`, `x1`, `y1` in PDF coordinates) is present on the flash card, the user-visible region inside the iframe should be **only that rectangle** (scaled), without relying on scrolling inside the iframe to find the card. Payload size and authoring flows are out of scope.

## Non-goals

- Reducing DOM size or image load (no “subset render” in this slice).
- Changing flash card authoring UI or `PdfSelectionScript` behavior.
- Altering recall scheduling, forms, or parent-page `flash_card_remember.js` unless required for layout.

## Approach: viewport clip (wrapper)

In `PdfPageHtmlRenderer`, when **both** are true:

- `mode == :study`, and  
- `resolved_initial_area_pdf` is non-nil (same rule as today: all four keys present on `areas_to_show` after stringify),

emit a **viewport wrapper** around the existing `.page` div:

1. **Outer viewport** (new class, e.g. `.flash-card-study-viewport`):
   - `overflow: hidden`
   - Explicit width and height in **scaled CSS pixels**:  
     `width = (x1 - x0) * scale`, `height = (y1 - y0) * scale`
   - Intersect the bbox with the layout `[0, width] × [0, height]` in PDF space so width/height never go negative or NaN; if intersection is empty, fall back to full-page rendering (no clip).

2. **Inner `.page`** (unchanged total size in PDF/scaled space):
   - Position so the bbox’s top-left aligns with the viewport’s top-left: e.g. `position: relative; left: -x0 * scale; top: -y0 * scale` (or an equivalent transform on `.page` only), preserving the existing coordinate system for all absolutely positioned children.

3. **Body / chrome**: Minimize margins on `body` in study mode when the viewport is used so the iframe’s document does not introduce extra scrollbars from default body margin. Keep `background` consistent with current study appearance where reasonable.

When the bbox is **missing or incomplete**, keep current markup: a single `<div class="page">` with full layout dimensions (no wrapper).

## Study script (`PdfFlashCardStudyScript`)

**Default:** No change to logic. Filtering uses boxes relative to `.page` and `INITIAL_AREA_PDF * SCALE`; moving `.page` inside a clipped viewport with a translation on `.page` should preserve relative offsets between `.page` and its descendants (verify with one text-only and one image+vector card).

If QA finds `getBoundingClientRect`-based intersection edge cases, the fallback fix is confined to the study script or the wrapper CSS, not a full coordinate rebase in the renderer.

## Parent page / iframe element

Optional follow-up in implementation: set iframe or container `aspect-ratio` / `max-height` from the same bbox so the **surrounding** Remember layout also hugs the region. Not required for the core “no in-iframe scroll” behavior if the iframe already has a bounded height and the clipped document fits.

## Testing

- **Service/renderer:** Extend or add tests around `PdfPageHtmlRenderer` / existing `pdf_page_html_renderer_test` so that for `mode: :study` with a valid `areas_to_show`, the generated HTML includes the viewport wrapper with expected width/height (substring or Nokogiri parse), and `.page` still exists inside it.
- **Regression:** Study mode **without** bbox still omits the wrapper and includes full `.page` dimensions as today.
- **Manual:** One flash card with images and vectors inside the bbox to confirm reveal order and `postMessage` progress unchanged.

## Risks

- Clamping/intersection bugs could hide all content; empty intersection must explicitly fall back to full page.
- Unusual bboxes (partially outside layout) must be clamped, not passed raw to CSS.

## Related code

- `plugins/book_plugin/app/services/book_plugin/pdf_page_html_renderer.rb` — `toolbar_and_page_open`, `header_css`, `selection_box_close`
- `plugins/book_plugin/app/services/book_plugin/pdf_flash_card_study_script.rb` — unchanged unless QA requires
- `plugins/book_plugin/app/views/book_plugin/flash_card_remember/index.html.erb` — iframe `srcdoc` call site (likely unchanged)
