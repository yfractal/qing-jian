document.addEventListener("click", function(event) {
  const button = event.target.closest("[data-flash-card-reveal-next]");
  if (!button) return;

  const frame = document.querySelector("[data-flash-card-study-frame]");
  if (!frame || !frame.contentWindow) return;

  frame.contentWindow.postMessage({ type: "flash-card-study-show-next-item" }, "*");
});

window.addEventListener("message", function(event) {
  if (!event.data || event.data.type !== "flash-card-reveal-progress") return;

  const progress = document.querySelector("[data-flash-card-reveal-progress]");
  const button = document.querySelector("[data-flash-card-reveal-next]");
  if (!progress || !button) return;

  const revealed = Number(event.data.revealed || 0);
  const total = Number(event.data.total || 0);
  progress.textContent = total === 0 ? "No items to reveal" : revealed + " / " + total;
  button.disabled = total === 0 || revealed >= total;
});

document.addEventListener("keydown", function(event) {
  if (event.defaultPrevented || event.altKey || event.ctrlKey || event.metaKey) return;
  const tag = (event.target && event.target.tagName) || "";
  if (tag === "INPUT" || tag === "TEXTAREA" || tag === "SELECT" || event.target.isContentEditable) return;

  const page = document.querySelector(".flash-card-remember-page");
  if (!page) return;

  if (event.code === "Space") {
    const btn = document.querySelector("[data-flash-card-reveal-next]");
    if (!btn || btn.disabled) return;
    event.preventDefault();
    btn.click();
    return;
  }

  if (event.key === "1") {
    const remembered = document.querySelector(
      "form.answer-form button[name='flash_card_recall_record[is_correct]'][value='true']"
    );
    if (remembered && !remembered.disabled) {
      event.preventDefault();
      remembered.click();
    }
    return;
  }

  if (event.key === "2") {
    const again = document.querySelector(
      "form.answer-form button[name='flash_card_recall_record[is_correct]'][value='false']"
    );
    if (again && !again.disabled) {
      event.preventDefault();
      again.click();
    }
  }
});
