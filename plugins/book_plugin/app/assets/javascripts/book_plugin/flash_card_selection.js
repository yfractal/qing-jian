(function () {
    const btnPickArea = document.getElementById("btn-pick-area");
    const btnPickText = document.getElementById("btn-pick-text");
    const page = document.querySelector(".page");
    const selectionBox = document.getElementById("selection-box");
    const config = window.__BOOK_PLUGIN_SELECTION_CONFIG__ || {};
    const SCALE = config.scale || 1;
    const INITIAL_AREA_PDF = config.initialAreaPdf || null;

    let mode = null;
    let startX = 0;
    let startY = 0;
    let isSelecting = false;
    let currentSelection = null;
    const rememberedTextIds = new Set();
    const pickedTextItems = [];
    let currentPickedTextItem = [];
    const currentPickedTextByElementId = new Map();

    function setMode(nextMode) {
        mode = nextMode;
        isSelecting = false;
        selectionBox.style.display = "none";
        btnPickArea.classList.toggle("is-active", mode === "area");
        btnPickText.classList.toggle("is-active", mode === "text");
    }

    btnPickArea.addEventListener("click", () => {
        setMode("area");
    });

    function buildPickedTextItemsForLog() {
        const items = pickedTextItems.map((item) => item.slice());
        if (currentPickedTextItem.length > 0) {
            items.push(currentPickedTextItem.slice());
        }
        return items;
    }

    function logPickedTextItems() {
        const items = buildPickedTextItemsForLog();
        console.log("Picked text items:", items);
        if (window.parent && window.parent !== window) {
            window.parent.postMessage(
                {
                    type: "picked-text-items-updated",
                    items: items
                },
                "*"
            );
        }
    }

    function startNewPickedTextItem() {
        if (currentPickedTextItem.length > 0) {
            pickedTextItems.push(currentPickedTextItem.slice());
        }
        currentPickedTextItem = [];
        currentPickedTextByElementId.clear();
        rememberedTextIds.clear();
        syncRememberedHighlights();
        logPickedTextItems();
    }

    btnPickText.addEventListener("click", () => {
        setMode("text");
        startNewPickedTextItem();
    });

    page.addEventListener("mousedown", (e) => {
        if (mode !== "area") return;

        const rect = page.getBoundingClientRect();
        startX = e.clientX - rect.left;
        startY = e.clientY - rect.top;
        isSelecting = true;

        selectionBox.style.left = startX + "px";
        selectionBox.style.top = startY + "px";
        selectionBox.style.width = "0px";
        selectionBox.style.height = "0px";
        selectionBox.style.display = "block";
    });

    page.addEventListener("mousemove", (e) => {
        if (mode !== "area" || !isSelecting) return;

        const rect = page.getBoundingClientRect();
        const x = e.clientX - rect.left;
        const y = e.clientY - rect.top;

        const w = x - startX;
        const h = y - startY;

        selectionBox.style.width = Math.abs(w) + "px";
        selectionBox.style.height = Math.abs(h) + "px";
        selectionBox.style.left = (w < 0 ? x : startX) + "px";
        selectionBox.style.top = (h < 0 ? y : startY) + "px";
    });

    function intersects(a, b) {
        return !(
            a.right < b.x0 ||
            a.left > b.x1 ||
            a.bottom < b.y0 ||
            a.top > b.y1
        );
    }

    function toPdfArea(area) {
        return {
            x0: area.x0 / SCALE,
            y0: area.y0 / SCALE,
            x1: area.x1 / SCALE,
            y1: area.y1 / SCALE
        };
    }

    function applySelection(area) {
        currentSelection = area;
        selectionBox.style.left = area.x0 + "px";
        selectionBox.style.top = area.y0 + "px";
        selectionBox.style.width = Math.max(0, area.x1 - area.x0) + "px";
        selectionBox.style.height = Math.max(0, area.y1 - area.y0) + "px";
        selectionBox.style.display = "block";
        filterElements(currentSelection);
    }

    function emitSelection(area) {
        const pdfArea = toPdfArea(area);
        console.log("Selected area (screen coords):", area);
        console.log("Selected area (PDF coords):", pdfArea);
        if (window.parent && window.parent !== window) {
            window.parent.postMessage(
                {
                    type: "pdf-area-selected",
                    area: area,
                    pdfArea: pdfArea
                },
                "*"
            );
        }
    }

    function syncRememberedHighlights() {
        document.querySelectorAll(".text.remembered").forEach((el) => {
            el.classList.remove("remembered");
        });
        rememberedTextIds.forEach((id) => {
            const el = document.getElementById(id);
            if (el && el.classList.contains("text")) {
                el.classList.add("remembered");
            }
        });
    }

    function collectTextTargetsForPick(e) {
        const selection = window.getSelection ? window.getSelection() : null;
        const selectedTargets = [];
        const selectedTargetIds = new Set();

        if (selection && selection.rangeCount > 0 && !selection.isCollapsed) {
            const textNodes = Array.from(document.querySelectorAll(".text"));
            for (let i = 0; i < selection.rangeCount; i += 1) {
                const range = selection.getRangeAt(i);
                textNodes.forEach((el) => {
                    if (selectedTargetIds.has(el.id)) return;
                    if (range.intersectsNode(el)) {
                        selectedTargetIds.add(el.id);
                        selectedTargets.push(el);
                    }
                });
            }
        }

        if (selectedTargets.length > 0) {
            return selectedTargets;
        }

        return Array.from(
            new Set(
                (document.elementsFromPoint(e.clientX, e.clientY) || [])
                    .map((el) => el.closest(".text"))
                    .filter(Boolean)
            )
        );
    }

    page.addEventListener("mouseup", () => {
        if (mode !== "area" || !isSelecting) return;
        isSelecting = false;

        const box = selectionBox.getBoundingClientRect();
        const pageRect = page.getBoundingClientRect();
        const area = {
            x0: box.left - pageRect.left,
            y0: box.top - pageRect.top,
            x1: box.right - pageRect.left,
            y1: box.bottom - pageRect.top
        };

        applySelection(area);
        emitSelection(area);
    });

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

    page.addEventListener("click", (e) => {
        if (mode !== "text") return;

        const targets = collectTextTargetsForPick(e);
        if (targets.length === 0) return;

        targets.forEach((target) => {
            const wasRemembered = rememberedTextIds.has(target.id);
            if (wasRemembered) {
                rememberedTextIds.delete(target.id);
            } else {
                rememberedTextIds.add(target.id);
            }

            if (wasRemembered) {
                const removedEntry = currentPickedTextByElementId.get(target.id);
                if (removedEntry) {
                    currentPickedTextItem = currentPickedTextItem.filter((entry) => entry.id !== removedEntry.id);
                }
                currentPickedTextByElementId.delete(target.id);
            } else {
                const text = target.innerText.trim();
                if (text) {
                    const entry = {
                        id: target.id,
                        text: text
                    };
                    currentPickedTextByElementId.set(target.id, entry);
                    currentPickedTextItem.push(entry);
                }
            }
        });
        syncRememberedHighlights();
        logPickedTextItems();
    });

    document.addEventListener("keydown", (e) => {
        if (e.key !== "r") return;

        document.querySelectorAll(".hidden").forEach((el) => el.classList.remove("hidden"));
        document.querySelectorAll("svg.vector-layer path").forEach((p) => {
            p.style.display = "";
        });
        selectionBox.style.display = "none";
        currentSelection = null;
        syncRememberedHighlights();
    });

    setMode("area");
    if (INITIAL_AREA_PDF) {
        const initialArea = {
            x0: INITIAL_AREA_PDF.x0 * SCALE,
            y0: INITIAL_AREA_PDF.y0 * SCALE,
            x1: INITIAL_AREA_PDF.x1 * SCALE,
            y1: INITIAL_AREA_PDF.y1 * SCALE
        };
        applySelection(initialArea);
    }
})();
