# frozen_string_literal: true

module BookPlugin
  class PdfFlashCardStudyScript
    class << self
      def build(scale:, initial_area:, initial_picked_text_groups:)
        area_json = initial_area.present? ? initial_area.to_json : "null"
        groups_json = initial_picked_text_groups.present? ? initial_picked_text_groups.to_json : "null"

        <<~JS
          (function () {
              const page = document.querySelector(".page");
              const SCALE = #{scale.to_f};
              const INITIAL_AREA_PDF = #{area_json};
              const INITIAL_PICKED_TEXT_GROUPS = #{groups_json};
              const revealItems = normalizePickedTextGroups(INITIAL_PICKED_TEXT_GROUPS).flat();
              let nextIndex = 0;

              function intersects(a, b) {
                  return !(
                      a.right < b.x0 ||
                      a.left > b.x1 ||
                      a.bottom < b.y0 ||
                      a.top > b.y1
                  );
              }

              function filterElements(selection) {
                  if (!selection) return;
                  const pageRect = page.getBoundingClientRect();
                  document.querySelectorAll(".text, .image").forEach((el) => {
                      const r = el.getBoundingClientRect();
                      const box = {
                          left: r.left - pageRect.left,
                          right: r.right - pageRect.left,
                          top: r.top - pageRect.top,
                          bottom: r.bottom - pageRect.top
                      };
                      el.classList.toggle("hidden", !intersects(box, selection));
                  });
                  document.querySelectorAll("svg.vector-layer path").forEach((p) => {
                      const box = {
                          left: parseFloat(p.dataset.x0) * SCALE,
                          right: parseFloat(p.dataset.x1) * SCALE,
                          top: parseFloat(p.dataset.y0) * SCALE,
                          bottom: parseFloat(p.dataset.y1) * SCALE
                      };
                      p.style.display = intersects(box, selection) ? "" : "none";
                  });
              }

              function normalizePickedTextGroups(raw) {
                  if (!raw || !Array.isArray(raw) || raw.length === 0) return [];
                  const first = raw[0];
                  if (typeof first === "string") {
                      const group = [];
                      raw.forEach((line) => {
                          const trimmed = String(line).trim();
                          if (!trimmed) return;
                          const el = Array.from(document.querySelectorAll(".text")).find(
                              (node) => node.innerText.trim() === trimmed
                          );
                          if (el) group.push({ id: el.id, text: trimmed });
                      });
                      return group.length ? [group] : [];
                  }
                  if (first && typeof first === "object" && !Array.isArray(first) && "id" in first && "text" in first) {
                      return [raw.map((entry) => ({ id: entry.id, text: entry.text }))];
                  }
                  return raw
                      .filter((g) => Array.isArray(g))
                      .map((g) =>
                          g.filter((e) => e && e.id && e.text).map((e) => ({ id: e.id, text: e.text }))
                      )
                      .filter((g) => g.length > 0);
              }

              function markRecallItems() {
                  revealItems.forEach((entry, index) => {
                      const el = document.getElementById(entry.id);
                      if (!el) return;
                      el.dataset.recallItemIndex = String(index);
                      el.classList.add("flash-card-hidden-recall-item");
                  });
                  highlightNextItem();
              }

              function highlightNextItem() {
                  document.querySelectorAll(".flash-card-next-recall-item").forEach((el) => {
                      el.classList.remove("flash-card-next-recall-item");
                  });
                  const entry = revealItems[nextIndex];
                  if (!entry) return;
                  const el = document.getElementById(entry.id);
                  if (el) el.classList.add("flash-card-next-recall-item");
              }

              function revealNextItem() {
                  const entry = revealItems[nextIndex];
                  if (!entry) return;
                  const el = document.getElementById(entry.id);
                  if (el) {
                      el.classList.remove("flash-card-hidden-recall-item");
                      el.classList.remove("flash-card-next-recall-item");
                      el.classList.add("flash-card-revealed-recall-item");
                  }
                  nextIndex += 1;
                  highlightNextItem();
                  emitProgress();
              }

              function emitProgress() {
                  if (window.parent && window.parent !== window) {
                      window.parent.postMessage(
                          {
                              type: "flash-card-reveal-progress",
                              revealed: nextIndex,
                              total: revealItems.length
                          },
                          "*"
                      );
                  }
              }

              function bindRefilterWhenImagesLoad(selection) {
                  document.querySelectorAll("img.image").forEach((img) => {
                      if (img.complete) return;
                      img.addEventListener(
                          "load",
                          () => {
                              if (selection) filterElements(selection);
                          },
                          { once: true }
                      );
                  });
              }

              function scheduleInitialAreaSelectionFromPdf() {
                  if (!INITIAL_AREA_PDF) return;

                  const initialArea = {
                      x0: INITIAL_AREA_PDF.x0 * SCALE,
                      y0: INITIAL_AREA_PDF.y0 * SCALE,
                      x1: INITIAL_AREA_PDF.x1 * SCALE,
                      y1: INITIAL_AREA_PDF.y1 * SCALE
                  };

                  function run() {
                      filterElements(initialArea);
                      bindRefilterWhenImagesLoad(initialArea);
                      markRecallItems();
                      emitProgress();
                  }

                  if (document.readyState === "complete") {
                      requestAnimationFrame(run);
                  } else {
                      window.addEventListener(
                          "load",
                          () => requestAnimationFrame(run),
                          { once: true }
                      );
                  }
              }

              window.addEventListener("message", (event) => {
                  if (!event.data || event.data.type !== "flash-card-study-show-next-item") return;
                  revealNextItem();
              });

              if (INITIAL_AREA_PDF) {
                  scheduleInitialAreaSelectionFromPdf();
              } else {
                  markRecallItems();
                  emitProgress();
              }
          })();
        JS
      end
    end
  end
end
