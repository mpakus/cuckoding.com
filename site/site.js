(() => {
  const scenes = [...document.querySelectorAll("[data-parallax]")].map(frame => ({
    frame,
    art: frame.querySelector("img"),
    ornament: frame.querySelector(".scene-ornament"),
  }));
  const toggle = document.querySelector("#motion-toggle");
  const reduced = window.matchMedia("(prefers-reduced-motion: reduce)");
  let paused = false;
  let pending = false;

  try { paused = localStorage.getItem("ccoding-parallax") === "paused"; } catch { /* Storage is optional. */ }

  function paint() {
    pending = false;
    const off = paused || reduced.matches;
    for (const { frame, art, ornament } of scenes) {
      const bounds = frame.getBoundingClientRect();
      // At 1.13 scale, 6% displacement stays inside the 6.5% overscan on each edge.
      const limit = Math.min(60, bounds.height * 0.06);
      const offset = off ? 0 : Math.max(-limit, Math.min(limit, (innerHeight / 2 - bounds.top - bounds.height / 2) * 0.2));
      art.style.transform = `translate3d(0, ${offset}px, 0) scale(1.13)`;
      if (ornament) ornament.style.transform = `translate3d(0, ${-offset * 0.5}px, 0) rotate(-8deg)`;
    }
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
