(() => {
  const art = document.querySelector("#arena-art");
  const frame = document.querySelector("#art-window");
  const toggle = document.querySelector("#motion-toggle");
  const reduced = window.matchMedia("(prefers-reduced-motion: reduce)");
  let paused = false;
  let pending = false;

  try { paused = localStorage.getItem("ccoding-parallax") === "paused"; } catch { /* Storage is optional. */ }

  function paint() {
    pending = false;
    const bounds = frame.getBoundingClientRect();
    const off = paused || reduced.matches;
    // Keep movement inside the image's 13% overscan, including short mobile views.
    const limit = Math.min(40, bounds.height * 0.06);
    const offset = off ? 0 : Math.max(-limit, Math.min(limit, (innerHeight / 2 - bounds.top - bounds.height / 2) * 0.09));
    art.style.setProperty("--parallax-y", `${offset}px`);
  }

  function schedule() {
    if (!pending && !paused && !reduced.matches) {
      pending = true;
      requestAnimationFrame(paint);
    }
  }

  function preference() {
    toggle.hidden = false;
    toggle.disabled = reduced.matches;
    toggle.setAttribute("aria-pressed", String(paused || reduced.matches));
    toggle.textContent = reduced.matches ? "Reduced motion on" : paused ? "Resume parallax" : "Pause parallax";
    paint();
  }

  toggle.addEventListener("click", () => {
    paused = !paused;
    try { localStorage.setItem("ccoding-parallax", paused ? "paused" : "running"); } catch { /* Storage is optional. */ }
    preference();
  });
  reduced.addEventListener("change", preference);
  window.addEventListener("scroll", schedule, { passive: true });
  window.addEventListener("resize", schedule);
  preference();
})();
