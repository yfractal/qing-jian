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
  progress.textContent = total === 0 ? "No picked items to reveal." : "Revealed " + revealed + " / " + total;
  button.disabled = total === 0 || revealed >= total;
});
