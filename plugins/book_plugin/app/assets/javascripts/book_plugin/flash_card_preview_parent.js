(function () {
  "use strict";

  function previewIframe() {
    return document.querySelector("iframe.book-html-preview-frame");
  }

  function isFromPreviewIframe(ev) {
    const frame = previewIframe();
    return frame && ev.source === frame.contentWindow;
  }

  function setAreasJson(pdfArea) {
    const el = document.getElementById("flash_card_areas_to_show");
    if (!el || pdfArea == null) return;
    el.value = JSON.stringify(pdfArea);
  }

  function setItemsTextFromPicked(items) {
    const el = document.getElementById("flash_card_items_to_remember_text");
    if (!el || !Array.isArray(items)) return;
    const lines = items
      .flatMap(function (group) {
        return Array.isArray(group) ? group : [];
      })
      .map(function (entry) {
        return entry && entry.text ? String(entry.text).trim() : "";
      })
      .filter(Boolean);
    el.value = lines.join("\n");
  }

  window.addEventListener("message", function (ev) {
    if (!isFromPreviewIframe(ev)) return;
    const data = ev.data;
    if (!data || typeof data !== "object") return;

    if (data.type === "pdf-area-selected") {
      setAreasJson(data.pdfArea);
      return;
    }
    if (data.type === "picked-text-items-updated") {
      setItemsTextFromPicked(data.items);
    }
  });
})();
