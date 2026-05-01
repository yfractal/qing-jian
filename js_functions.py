def build_selection_js(scale):
    return f"""
(function () {{
    const page = document.querySelector(".page");
    const selectionBox = document.getElementById("selection-box");
    const SCALE = {scale};

    let startX = 0;
    let startY = 0;
    let isSelecting = false;
    let selection = null;

    page.addEventListener("mousedown", (e) => {{
        const rect = page.getBoundingClientRect();
        startX = e.clientX - rect.left;
        startY = e.clientY - rect.top;
        isSelecting = true;

        selectionBox.style.left = startX + "px";
        selectionBox.style.top = startY + "px";
        selectionBox.style.width = "0px";
        selectionBox.style.height = "0px";
        selectionBox.style.display = "block";
    }});

    page.addEventListener("mousemove", (e) => {{
        if (!isSelecting) return;

        const rect = page.getBoundingClientRect();
        const x = e.clientX - rect.left;
        const y = e.clientY - rect.top;

        const w = x - startX;
        const h = y - startY;

        selectionBox.style.width = Math.abs(w) + "px";
        selectionBox.style.height = Math.abs(h) + "px";
        selectionBox.style.left = (w < 0 ? x : startX) + "px";
        selectionBox.style.top = (h < 0 ? y : startY) + "px";
    }});

    page.addEventListener("mouseup", () => {{
        isSelecting = false;

        const box = selectionBox.getBoundingClientRect();
        const pageRect = page.getBoundingClientRect();

        selection = {{
            x0: box.left - pageRect.left,
            y0: box.top - pageRect.top,
            x1: box.right - pageRect.left,
            y1: box.bottom - pageRect.top
        }};

        filterElements();
    }});

    function intersects(a, b) {{
        return !(
            a.right < b.x0 ||
            a.left > b.x1 ||
            a.bottom < b.y0 ||
            a.top > b.y1
        );
    }}

    function filterElements() {{
        if (!selection) return;

        const pageRect = page.getBoundingClientRect();

        document.querySelectorAll(".text, .image").forEach(el => {{
            const r = el.getBoundingClientRect();
            const box = {{
                left: r.left - pageRect.left,
                right: r.right - pageRect.left,
                top: r.top - pageRect.top,
                bottom: r.bottom - pageRect.top
            }};

            el.classList.toggle("hidden", !intersects(box, selection));
        }});

        document.querySelectorAll("svg.vector-layer path").forEach(p => {{
            const box = {{
                left: parseFloat(p.dataset.x0) * SCALE,
                right: parseFloat(p.dataset.x1) * SCALE,
                top: parseFloat(p.dataset.y0) * SCALE,
                bottom: parseFloat(p.dataset.y1) * SCALE
            }};

            p.style.display = intersects(box, selection) ? "" : "none";
        }});
    }}

    document.addEventListener("keydown", (e) => {{
        if (e.key !== "r") return;

        document.querySelectorAll(".hidden").forEach(el => el.classList.remove("hidden"));
        document.querySelectorAll("svg.vector-layer path").forEach(p => p.style.display = "");
        selectionBox.style.display = "none";
        selection = null;
    }});
}})();
"""
