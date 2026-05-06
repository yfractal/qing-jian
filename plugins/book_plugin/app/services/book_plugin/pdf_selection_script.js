
(function () {
    const btnPickArea = document.getElementById("btn-pick-area");
    const btnPickText = document.getElementById("btn-pick-text");
    const page = document.querySelector(".page");
    const selectionBox = document.getElementById("selection-box");
    const SCALE = 1.0;
    const INITIAL_AREA_PDF = null;
    const INITIAL_PICKED_TEXT_GROUPS = null;
    const INITIAL_VECTOR_ADJUSTMENTS = [];

    let mode = null;
    let startX = 0;
    let startY = 0;
    let isSelecting = false;
    let currentSelection = null;
    const rememberedTextIds = new Set();
    const pickedTextItems = [];
    let currentPickedTextItem = [];
    const currentPickedTextByElementId = new Map();

    let draggingPath = null;
    let dragStart = null;

    function applyPathTransform(path, dx, dy) {
        path.dataset.dx = String(dx);
        path.dataset.dy = String(dy);
        path.setAttribute("transform", `translate(${dx}, ${dy})`);
    }

    function getVectorAdjustments() {
        return Array.from(document.querySelectorAll("svg.vector-layer path"))
            .map((p) => ({
                path_id: p.id,
                dx: parseFloat(p.dataset.dx || "0"),
                dy: parseFloat(p.dataset.dy || "0")
            }))
            .filter((v) => v.path_id && (v.dx !== 0 || v.dy !== 0));
    }

    window.getVectorAdjustments = getVectorAdjustments;

    function emitVectorAdjustments() {
        const adjustments = getVectorAdjustments();
        if (window.parent && window.parent !== window) {
            window.parent.postMessage(
                {
                    type: "vector-adjustments-updated",
                    adjustments: adjustments
                },
                "*"
            );
        }
    }

    function hydrateVectorAdjustments() {
        if (!Array.isArray(INITIAL_VECTOR_ADJUSTMENTS)) return;

        INITIAL_VECTOR_ADJUSTMENTS.forEach((entry) => {
            if (!entry || !entry.path_id) return;
            const el = document.getElementById(entry.path_id);
            if (!el) return;
            applyPathTransform(el, Number(entry.dx) || 0, Number(entry.dy) || 0);
        });
    }

    function wirePathDragging() {
        document.querySelectorAll("svg.vector-layer path").forEach((path) => {
            path.addEventListener("mousedown", (e) => {
                e.stopPropagation();
                if (mode !== "area") return;

                draggingPath = path;
                dragStart = {
                    x: e.clientX,
                    y: e.clientY,
                    dx: parseFloat(path.dataset.dx || "0"),
                    dy: parseFloat(path.dataset.dy || "0")
                };
            });
        });

        document.addEventListener("mousemove", (e) => {
            if (!draggingPath || !dragStart) return;
            const nextDx = dragStart.dx + (e.clientX - dragStart.x) / SCALE;
            const nextDy = dragStart.dy + (e.clientY - dragStart.y) / SCALE;
            applyPathTransform(draggingPath, nextDx, nextDy);
        });

        document.addEventListener("mouseup", () => {
            if (!draggingPath) return;
            draggingPath = null;
            dragStart = null;
            emitVectorAdjustments();
        });
    }

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
            const dx = parseFloat(p.dataset.dx || "0");
            const dy = parseFloat(p.dataset.dy || "0");
            const box = {
                left: (parseFloat(p.dataset.x0) + dx) * SCALE,
                right: (parseFloat(p.dataset.x1) + dx) * SCALE,
                top: (parseFloat(p.dataset.y0) + dy) * SCALE,
                bottom: (parseFloat(p.dataset.y1) + dy) * SCALE
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
                g
                    .filter((e) => e && e.id && e.text)
                    .map((e) => ({ id: e.id, text: e.text }))
            )
            .filter((g) => g.length > 0);
    }

    function hydratePickedTextFromInitial() {
        const groups = normalizePickedTextGroups(INITIAL_PICKED_TEXT_GROUPS);
        if (groups.length === 0) return false;

        pickedTextItems.length = 0;
        groups.forEach((g) => pickedTextItems.push(g.slice()));

        currentPickedTextItem.length = 0;
        currentPickedTextByElementId.clear();
        rememberedTextIds.clear();

        const last = groups[groups.length - 1];
        last.forEach((entry) => {
            currentPickedTextByElementId.set(entry.id, entry);
        });

        groups.forEach((g) => {
            g.forEach((entry) => rememberedTextIds.add(entry.id));
        });

        syncRememberedHighlights();
        logPickedTextItems();
        return true;
    }

    function bindRefilterWhenImagesLoad() {
        document.querySelectorAll("img.image").forEach((img) => {
            if (img.complete) return;
            img.addEventListener(
                "load",
                () => {
                    if (currentSelection) filterElements(currentSelection);
                },
                { once: true }
            );
        });
    }

    function scheduleInitialAreaSelectionFromPdf() {
        const initialArea = {
            x0: INITIAL_AREA_PDF.x0 * SCALE,
            y0: INITIAL_AREA_PDF.y0 * SCALE,
            x1: INITIAL_AREA_PDF.x1 * SCALE,
            y1: INITIAL_AREA_PDF.y1 * SCALE
        };
        function run() {
            applySelection(initialArea);
            bindRefilterWhenImagesLoad();
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

    if (INITIAL_AREA_PDF) {
        setMode("area");
        scheduleInitialAreaSelectionFromPdf();
    } else {
        setMode("text");
    }

    const hydrated = hydratePickedTextFromInitial();
    if (!hydrated && !INITIAL_AREA_PDF) {
        startNewPickedTextItem();
    }

    hydrateVectorAdjustments();
    wirePathDragging();
})();
